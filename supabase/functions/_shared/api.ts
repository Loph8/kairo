// The single `api` edge function's logic, behind Db interfaces so it is tested in bun with a fake.
// Every request carries a verified user; the family and member always come from that user, never the body.
import type { BusyBlock } from './calendar.ts';
import { DEMO_LEDGER, FAMILY, TRUTH_BANDS } from './family.ts';
import { CONTACT_APPS, familyPickup, familyState, ledgerOf, type BookingRow, type Contact, type FamilyInputs, type FamilyState,
         type MemberRow, type StoredObservation } from './familyState.ts';
import { levelOf, type Level, type Onboarding, type Outcome } from './learning.ts';
import { noteFor, type NoteWriter } from './notes.ts';
import { chargeLedger, type Ledger } from './schedule.ts';
import { seedObservations } from './seed.ts';
import { SLOT_MS } from './time.ts';

export const MAX_BLOCKS = 600;            // about 4 past weeks + 1 week ahead of meetings
/** Past meetings older than this are dropped: the learner has faded them out anyway. */
export const KEEP_BLOCKS_MS = 8 * 7 * 24 * 3600 * 1000;
export const MAX_BLOCK_HOURS = 24;
export const MAX_REPLY_SECONDS = 7 * 24 * 3600;
export const JOIN_HORIZON_MS = 7 * 24 * 3600 * 1000;
export const MAX_MEMBERS = 8;
/** How many families one account can belong to. */
export const MAX_FAMILIES = 5;
const CLIENT_SOURCES = ['channel', 'family_call', 'widget', 'shortcut'] as const;
const SIM_EVENTS = ['answer_call', 'miss_call', 'reply_fast', 'no_reply', 'free', 'busy'] as const;
type SimEvent = typeof SIM_EVENTS[number];

/** One family's rows. */
export interface Db {
  load(): Promise<FamilyInputs>;
  addMember(row: MemberRow & { userId: string | null }): Promise<void>;
  addObservations(rows: readonly StoredObservation[]): Promise<void>;
  /** Replaces the member's blocks that end after `from` and keeps older ones (past meetings teach the learner). */
  replaceBusyBlocks(memberId: string, blocks: readonly BusyBlock[], from: Date): Promise<void>;
  dropBlocksBefore(cutoff: Date): Promise<void>;
  findOpenBooking(start: Date): Promise<BookingRow | null>;
  createBooking(start: Date, levels: Record<string, Level>): Promise<BookingRow>;
  acceptBooking(id: string, memberIds: readonly string[]): Promise<BookingRow>;
  setBurden(ledger: Ledger): Promise<void>;
  /** Clears outcomes, calendar blocks and bookings, removes simulated members, zeroes burden. */
  clearHistory(): Promise<void>;
  getNote(key: string): Promise<string | null>;
  putNote(key: string, text: string): Promise<void>;
}

/** callLink: the family's shared group-call link (FaceTime, Zoom, Meet…), set by anyone in it. */
export interface Membership {
  familyId: string; familyName: string; inviteCode: string; callLink: string | null; memberId: string;
  /** Who last started a group call and when, so everyone else can be shown Join. */
  groupCall?: GroupCall | null;
}
export interface GroupCall { startedBy: string; at: string }
/** How long a started group call shows a Join button for everyone else. */
export const GROUP_CALL_SHOWN_MS = 45 * 60_000;

/** Who belongs where. */
export interface Directory {
  /** Every family this user is in, oldest first. */
  memberships(userId: string): Promise<Membership[]>;
  createFamily(name: string): Promise<{ familyId: string; inviteCode: string }>;
  familyByCode(code: string): Promise<{ familyId: string; familyName: string; memberCount: number } | null>;
  family(familyId: string): Db;
  /** Removes the member and their history. Deletes the family when no real person is left in it. */
  leaveFamily(m: Membership): Promise<void>;
  /** Sets or clears (null) the family's group-call link. */
  setCallLink(familyId: string, link: string | null): Promise<void>;
  startGroupCall(familyId: string, memberId: string, at: Date): Promise<void>;
  /** Saves the user's number and connected apps on every family they're in. */
  setContact(userId: string, contact: Contact): Promise<void>;
}

export interface Caller { readonly userId: string; readonly email: string | null }

export class ApiError extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}

export interface FamilyRef { familyId: string; familyName: string; inviteCode: string; callLink: string | null; groupCall: GroupCall | null }
/** The family this response is about, plus every family the user can switch to. */
export interface AccountView extends FamilyRef { email: string | null; memberId: string; families: FamilyRef[] }
export type ApiResult = {
  ok: true;
  account: AccountView | null;
  state: (FamilyState & { note: string | null }) | null;
  booking?: { id: string; status: string; acceptedBy: string[] };
};

export interface Deps { dir: Directory; notes?: NoteWriter; newId: () => string; inviteCode: () => string }

export async function handle(body: unknown, caller: Caller, deps: Deps, now: Date): Promise<ApiResult> {
  const req = asRecord(body, 'body');
  const action = str(req.action, 'action');
  const mine = await deps.dir.memberships(caller.userId);
  if (action === 'create_family') return createFamily(req, caller, deps, now, mine);
  if (action === 'join_family') return joinFamily(req, caller, deps, now, mine);

  const me = pickFamily(mine, req.family_id);
  if (action === 'me' && !me) return { ok: true, account: null, state: null };
  if (!me) throw new ApiError(409, 'create or join a family first');
  const db = deps.dir.family(me.familyId);
  const ctx: Ctx = { me, mine, caller, db, deps, now };

  switch (action) {
    case 'me':
    case 'state': return result(ctx);
    case 'log_outcome': return logOutcome(req, ctx);
    case 'push_busy': return pushBusy(req, ctx);
    case 'join': return join(req, ctx);
    case 'simulate': return simulate(req, ctx);
    case 'add_demo_family': return addDemoFamily(ctx);
    case 'reset_family': await db.clearHistory(); return result(ctx);
    case 'leave_family': return leaveFamily(ctx);
    case 'set_call_link': return setCallLink(req, ctx);
    case 'start_group_call': return startGroupCall(ctx);
    case 'set_contact': return setContact(req, ctx);
    default: throw new ApiError(400, `unknown action "${action}"`);
  }
}

interface Ctx { me: Membership; mine: readonly Membership[]; caller: Caller; db: Db; deps: Deps; now: Date }

/**
 * The family a request is about. Phones send the family they have open as `family_id`.
 * An unknown id (for example a family left on another phone) falls back to the oldest family,
 * and the response says which one it used, so the phone can follow.
 */
function pickFamily(mine: readonly Membership[], familyId: unknown): Membership | null {
  if (familyId === undefined || familyId === null) return mine[0] ?? null;
  const id = str(familyId, 'family_id', 64);
  return mine.find((m) => m.familyId === id) ?? mine[0] ?? null;
}

function ctxFor(me: Membership, mine: readonly Membership[], caller: Caller, deps: Deps, now: Date): Ctx {
  return { me, mine, caller, db: deps.dir.family(me.familyId), deps, now };
}

async function result(ctx: Ctx, booking?: ApiResult['booking']): Promise<ApiResult> {
  const data = await ctx.db.load();
  const state = familyState(data, ctx.now, false);
  const note = await noteFor(state, ctx.me.memberId, ctx.db, ctx.deps.notes);
  return { ok: true, account: accountView(ctx), state: { ...state, note }, ...(booking ? { booking } : {}) };
}

const familyRef = (m: Membership): FamilyRef =>
  ({ familyId: m.familyId, familyName: m.familyName, inviteCode: m.inviteCode, callLink: m.callLink, groupCall: m.groupCall ?? null });

const fresh = (ref: FamilyRef, now: Date): FamilyRef =>
  (ref.groupCall && now.getTime() - Date.parse(ref.groupCall.at) > GROUP_CALL_SHOWN_MS ? { ...ref, groupCall: null } : ref);

const accountView = (ctx: Ctx): AccountView =>
  ({ ...fresh(familyRef(ctx.me), ctx.now), email: ctx.caller.email, memberId: ctx.me.memberId, families: ctx.mine.map((m) => fresh(familyRef(m), ctx.now)) });

// ---- accounts ----

function checkRoomForAnotherFamily(mine: readonly Membership[]) {
  if (mine.length >= MAX_FAMILIES) throw new ApiError(409, `you can be in at most ${MAX_FAMILIES} families`);
}

async function createFamily(req: Record<string, unknown>, caller: Caller, deps: Deps, now: Date,
                            mine: readonly Membership[]): Promise<ApiResult> {
  checkRoomForAnotherFamily(mine);
  const familyName = str(req.family_name, 'family_name', 60);
  const profile = parseProfile(req);
  const { familyId, inviteCode } = await deps.dir.createFamily(familyName);
  const memberId = deps.newId();
  await deps.dir.family(familyId).addMember({ ...profile, id: memberId, userId: caller.userId, burdenMin: 0, simulated: false, persona: null });
  if (profile.contact) await deps.dir.setContact(caller.userId, profile.contact);
  const me: Membership = { familyId, familyName, inviteCode, callLink: null, memberId };
  return result(ctxFor(me, [...mine, me], caller, deps, now));
}

async function joinFamily(req: Record<string, unknown>, caller: Caller, deps: Deps, now: Date,
                          mine: readonly Membership[]): Promise<ApiResult> {
  const code = str(req.invite_code, 'invite_code', 12).trim().toUpperCase();
  const family = await deps.dir.familyByCode(code);
  if (!family) throw new ApiError(404, 'no family has that invite code');
  if (mine.some((m) => m.familyId === family.familyId)) throw new ApiError(409, 'you are already in this family');
  checkRoomForAnotherFamily(mine);
  if (family.memberCount >= MAX_MEMBERS) throw new ApiError(409, `a family can have at most ${MAX_MEMBERS} people`);
  const profile = parseProfile(req);
  const memberId = deps.newId();
  const db = deps.dir.family(family.familyId);
  await db.addMember({ ...profile, id: memberId, userId: caller.userId, burdenMin: 0, simulated: false, persona: null });
  if (profile.contact) await deps.dir.setContact(caller.userId, profile.contact);
  const after = await deps.dir.memberships(caller.userId);
  const me = after.find((m) => m.familyId === family.familyId);
  if (!me) throw new ApiError(500, 'join did not stick');
  return result({ me, mine: after, caller, db, deps, now });
}

/** Leaves the family the request is about and opens the next one, if the user has another. */
async function leaveFamily(ctx: Ctx): Promise<ApiResult> {
  await ctx.deps.dir.leaveFamily(ctx.me);
  const rest = await ctx.deps.dir.memberships(ctx.caller.userId);
  const next = rest[0];
  if (!next) return { ok: true, account: null, state: null };
  return result(ctxFor(next, rest, ctx.caller, ctx.deps, ctx.now));
}

/** Your number and connected call apps. Saved on every family you're in, so you set them once. */
async function setContact(req: Record<string, unknown>, ctx: Ctx): Promise<ApiResult> {
  const contact = parseContact(req);
  if (!contact) throw new ApiError(400, 'phone or apps is required');
  await ctx.deps.dir.setContact(ctx.caller.userId, contact);
  return result(ctx);
}

/** E.164: +, country code, number. Spaces, dashes, dots and brackets are stripped first. */
export function parsePhone(v: unknown): string | null {
  if (v === null || v === '') return null;
  const s = str(v, 'phone', 32).replace(/[\s\-().]/g, '');
  if (!/^\+[1-9]\d{6,14}$/.test(s)) throw new ApiError(400, 'phone must include the country code, like +1 919 555 0123');
  return s;
}

/** Undefined when the request carries neither field (older apps), so nothing is overwritten. */
function parseContact(req: Record<string, unknown>): Contact | undefined {
  if (req.phone === undefined && req.apps === undefined) return undefined;
  const phone = parsePhone(req.phone ?? null);
  const raw = req.apps === undefined || req.apps === null ? {} : asRecord(req.apps, 'apps');
  const apps: Record<string, string> = {};
  for (const [k, v] of Object.entries(raw)) {
    if (!(CONTACT_APPS as readonly string[]).includes(k)) throw new ApiError(400, `apps.${k} is not a supported app`);
    if (v === null || v === '') continue;
    apps[k] = str(v, `apps.${k}`, 64).trim();
  }
  return { phone, apps };
}

/** Marks that you just opened the family's group call, so everyone else sees "<you> started a call · Join". */
async function startGroupCall(ctx: Ctx): Promise<ApiResult> {
  if (!ctx.me.callLink) throw new ApiError(409, 'set a group call link first');
  await ctx.deps.dir.startGroupCall(ctx.me.familyId, ctx.me.memberId, ctx.now);
  const groupCall: GroupCall = { startedBy: ctx.me.memberId, at: ctx.now.toISOString() };
  const update = (m: Membership): Membership => (m.familyId === ctx.me.familyId ? { ...m, groupCall } : m);
  return result({ ...ctx, me: update(ctx.me), mine: ctx.mine.map(update) });
}

/** Anyone in the family can set the shared link; everyone's Group call button then opens it. */
async function setCallLink(req: Record<string, unknown>, ctx: Ctx): Promise<ApiResult> {
  const link = parseCallLink(req.link);
  await ctx.deps.dir.setCallLink(ctx.me.familyId, link);
  const update = (m: Membership): Membership => (m.familyId === ctx.me.familyId ? { ...m, callLink: link } : m);
  return result({ ...ctx, me: update(ctx.me), mine: ctx.mine.map(update) });
}

/** Group-call services whose links open straight into a call. Anything else is refused, so no one can plant a look-alike page. */
export const CALL_LINK_HOSTS = [
  'facetime.apple.com', 'meet.google.com', 'zoom.us', 'call.whatsapp.com',
  'teams.microsoft.com', 'teams.live.com', 'whereby.com', 'meet.jit.si',
] as const;

function parseCallLink(v: unknown): string | null {
  if (v === null || v === undefined || v === '') return null;
  const raw = str(v, 'link', 500).trim();
  let url: URL;
  try { url = new URL(raw); } catch { throw new ApiError(400, 'link is not a web address'); }
  const host = url.hostname.toLowerCase();
  const known = CALL_LINK_HOSTS.some((h) => host === h || host.endsWith(`.${h}`));
  if (url.protocol !== 'https:' || !known) {
    throw new ApiError(400, 'use a FaceTime, Google Meet, Zoom, WhatsApp, Teams, Whereby or Jitsi link');
  }
  return url.toString();
}

function parseProfile(req: Record<string, unknown>) {
  const name = str(req.name, 'name', 40).trim();
  const tz = str(req.tz, 'tz', 60);
  try { new Intl.DateTimeFormat('en-US', { timeZone: tz }); } catch { throw new ApiError(400, 'tz is not a time zone'); }
  const city = req.city === undefined ? '' : str(req.city, 'city', 60, true);
  const busy = req.busy === undefined ? [] : asArray(req.busy, 'busy', 4).map((b, i) => {
    const pair = asArray(b, `busy[${i}]`, 2);
    return [hhmm(pair[0], `busy[${i}][0]`), hhmm(pair[1], `busy[${i}][1]`)] as const;
  });
  const onboarding: Onboarding = { wake: hhmm(req.wake ?? '07:00', 'wake'), bed: hhmm(req.bed ?? '23:00', 'bed'), busy };
  return { name, tz, city, onboarding, contact: parseContact(req) };
}

// ---- signals ----

async function familyMember(ctx: Ctx, id: string) {
  const data = await ctx.db.load();
  const member = data.members.find((m) => m.id === id);
  if (!member) throw new ApiError(404, 'that person is not in your family');
  return { data, member };
}

/** About yourself (widget/label/channel) or, for calls you placed and texts you received, about the other person. */
async function logOutcome(req: Record<string, unknown>, ctx: Ctx): Promise<ApiResult> {
  const memberId = req.member_id === undefined ? ctx.me.memberId : str(req.member_id, 'member_id');
  await familyMember(ctx, memberId);
  const source = oneOf(req.source ?? 'channel', CLIENT_SOURCES, 'source');
  const at = req.at === undefined ? ctx.now : date(req.at, 'at');
  if (at.getTime() > ctx.now.getTime() + 60_000) throw new ApiError(400, 'at is in the future');
  const outcome = parseOutcome(req);
  if (memberId !== ctx.me.memberId && outcome.kind === 'label') throw new ApiError(403, 'only they can mark themselves free or busy');
  // Whoever placed the call was free to talk then, whether or not the other person picked up.
  const callerWasFree = outcome.kind === 'call' && memberId !== ctx.me.memberId
    ? [{ memberId: ctx.me.memberId, at, outcome: { kind: 'call' as const, answered: true }, source }] : [];
  await ctx.db.addObservations([{ memberId, at, outcome, source }, ...callerWasFree]);
  return result(ctx);
}

/** Only timing and outcome are accepted. Any `text`/`body` field is rejected, not silently dropped. */
function parseOutcome(req: Record<string, unknown>): Outcome {
  if ('text' in req || 'body' in req || 'message' in req) throw new ApiError(400, 'message content is never accepted');
  const kind = oneOf(req.kind, ['call', 'text', 'label'] as const, 'kind');
  if (kind === 'call') return { kind, answered: bool(req.answered, 'answered') };
  if (kind === 'label') return { kind, free: bool(req.free, 'free') };
  if (req.reply_seconds === null) return { kind, replySeconds: null };
  const s = num(req.reply_seconds, 'reply_seconds');
  if (s < 0 || s > MAX_REPLY_SECONDS) throw new ApiError(400, 'reply_seconds out of range');
  return { kind, replySeconds: Math.round(s) };
}

async function pushBusy(req: Record<string, unknown>, ctx: Ctx): Promise<ApiResult> {
  const memberId = ctx.me.memberId;
  const raw = asArray(req.blocks, 'blocks', MAX_BLOCKS);
  const blocks = raw.map((r, i): BusyBlock => {
    const b = asRecord(r, `blocks[${i}]`);
    const start = date(b.start, `blocks[${i}].start`), end = date(b.end, `blocks[${i}].end`);
    const hours = (end.getTime() - start.getTime()) / 3_600_000;
    if (hours <= 0 || hours > MAX_BLOCK_HOURS) throw new ApiError(400, `blocks[${i}] must last 0–${MAX_BLOCK_HOURS} h`);
    const id = str(b.id, `blocks[${i}].id`, 128);
    return { id, memberId, start, end, movable: b.movable === undefined ? false : bool(b.movable, `blocks[${i}].movable`) };
  });
  // The phone sends a window (past weeks + days ahead). Everything in that window is replaced, older history is kept.
  const from = new Date(Math.min(ctx.now.getTime(), ...blocks.map((b) => b.start.getTime())));
  await ctx.db.replaceBusyBlocks(memberId, blocks, from);
  await ctx.db.dropBlocksBefore(new Date(ctx.now.getTime() - KEEP_BLOCKS_MS));
  return result(ctx);
}

async function join(req: Record<string, unknown>, ctx: Ctx): Promise<ApiResult> {
  const { now, db } = ctx;
  const data = await db.load();
  const start = date(req.start, 'start');
  if (start.getTime() % SLOT_MS !== 0) throw new ApiError(400, 'start must be on a half-hour');
  if (start.getTime() <= now.getTime()) throw new ApiError(409, 'that time has passed');
  if (start.getTime() - now.getTime() > JOIN_HORIZON_MS) throw new ApiError(400, 'start is too far ahead');

  const opened = (await db.findOpenBooking(start)) ?? await db.createBooking(start, levelsAt(data, start, now));
  const before = opened.status;
  // Simulated relatives say yes for themselves, so one phone can demo the whole family.
  const simulated = data.members.filter((m) => m.simulated).map((m) => m.id);
  const booking = await db.acceptBooking(opened.id, [ctx.me.memberId, ...simulated]);
  if (before !== 'booked' && booking.status === 'booked') {
    await db.setBurden(chargeLedger(ledgerOf(data.members), booking.levels));   // fairness: charge once
  }
  return result(ctx, { id: booking.id, status: booking.status, acceptedBy: [...booking.acceptedBy] });
}

function levelsAt(data: FamilyInputs, start: Date, now: Date): Record<string, Level> {
  const pickupAt = familyPickup(data, now);
  const mid = new Date(start.getTime() + SLOT_MS / 2);
  return Object.fromEntries(data.members.map((m) => [m.id, levelOf(pickupAt(m.id, mid))]));
}

/** Demo controls: make a simulated relative answer, miss, reply or tap — and watch the AI learn. */
async function simulate(req: Record<string, unknown>, ctx: Ctx): Promise<ApiResult> {
  const { member } = await familyMember(ctx, str(req.member_id, 'member_id'));
  if (!member.simulated) throw new ApiError(403, 'only simulated family members can be driven from the demo');
  const event = oneOf(req.event, SIM_EVENTS, 'event');
  await ctx.db.addObservations([{ memberId: member.id, at: ctx.now, outcome: simOutcome(event), source: 'sim' }]);
  return result(ctx);
}

function simOutcome(e: SimEvent): Outcome {
  switch (e) {
    case 'answer_call': return { kind: 'call', answered: true };
    case 'miss_call': return { kind: 'call', answered: false };
    case 'reply_fast': return { kind: 'text', replySeconds: 90 };
    case 'no_reply': return { kind: 'text', replySeconds: null };
    case 'free': return { kind: 'label', free: true };
    case 'busy': return { kind: 'label', free: false };
  }
}

/**
 * Adds Mom and Grandpa in Seoul and Dad in Addis Ababa as simulated relatives, each with two weeks of
 * seeded calls and texts, and seeds the same for you so the heatmaps have something to show at once.
 */
async function addDemoFamily(ctx: Ctx): Promise<ApiResult> {
  const { db, now, deps } = ctx;
  await db.clearHistory();
  const data = await db.load();
  const me = data.members.find((m) => m.id === ctx.me.memberId);
  if (!me) throw new ApiError(500, 'your member row is missing');
  const relatives = FAMILY.filter((f) => f.id !== 'you');
  if (data.members.length + relatives.length > MAX_MEMBERS) throw new ApiError(409, 'your family is too big for the demo relatives');

  const rows = relatives.map((f) => ({ ...f, id: deps.newId(), userId: null, simulated: true, persona: f.id,
                                        burdenMin: DEMO_LEDGER[f.id] ?? 0 }));
  for (const row of rows) await db.addMember(row);
  const seeded = [
    ...seedObservations(me, TRUTH_BANDS.you ?? [], now).map((o) => ({ ...o, memberId: me.id, historical: true })),
    ...rows.flatMap((r) => seedObservations(r, TRUTH_BANDS[r.persona] ?? [], now).map((o) => ({ ...o, memberId: r.id, historical: true }))),
  ];
  await db.addObservations(seeded);
  return result(ctx);
}

// ---- input checks ----
function asRecord(v: unknown, name: string): Record<string, unknown> {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) throw new ApiError(400, `${name} must be an object`);
  return v as Record<string, unknown>;
}
function asArray(v: unknown, name: string, max: number): unknown[] {
  if (!Array.isArray(v)) throw new ApiError(400, `${name} must be an array`);
  if (v.length > max) throw new ApiError(400, `at most ${max} items in ${name}`);
  return v;
}
function str(v: unknown, name: string, max = 200, allowEmpty = false): string {
  if (typeof v !== 'string' || (!allowEmpty && v.trim().length === 0) || v.length > max) {
    throw new ApiError(400, `${name} must be a non-empty string up to ${max} characters`);
  }
  return v;
}
function hhmm(v: unknown, name: string): string {
  if (typeof v !== 'string' || !/^([01]\d|2[0-4]):[0-5]\d$/.test(v)) throw new ApiError(400, `${name} must look like 07:30`);
  return v;
}
function num(v: unknown, name: string): number {
  if (typeof v !== 'number' || !Number.isFinite(v)) throw new ApiError(400, `${name} must be a number`);
  return v;
}
function bool(v: unknown, name: string): boolean {
  if (typeof v !== 'boolean') throw new ApiError(400, `${name} must be true or false`);
  return v;
}
function date(v: unknown, name: string): Date {
  const d = typeof v === 'string' ? new Date(v) : null;
  if (!d || Number.isNaN(d.getTime())) throw new ApiError(400, `${name} must be an ISO date`);
  return d;
}
function oneOf<T extends string>(v: unknown, allowed: readonly T[], name: string): T {
  if (typeof v !== 'string' || !(allowed as readonly string[]).includes(v)) {
    throw new ApiError(400, `${name} must be one of ${allowed.join(', ')}`);
  }
  return v as T;
}
