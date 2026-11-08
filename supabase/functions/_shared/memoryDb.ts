// In-memory Directory + per-family Db with the same rules as the SQL: one family per user, one open
// booking per slot, booked when everyone in that family is in. Used by tests.
import type { Db, Directory, GroupCall, Membership } from './api.ts';
import type { BusyBlock } from './calendar.ts';
import type { BookingRow, Contact, MemberRow, StoredObservation } from './familyState.ts';
import type { Level } from './learning.ts';
import type { Ledger } from './schedule.ts';

interface Family { id: string; name: string; inviteCode: string; callLink: string | null; groupCall?: GroupCall | null }
type Owned<T> = T & { familyId: string };
type MemberRecord = Owned<MemberRow & { userId: string | null }>;

export class MemoryDirectory implements Directory {
  families: Family[] = [];
  members: MemberRecord[] = [];
  observations: Owned<StoredObservation>[] = [];
  blocks: Owned<BusyBlock>[] = [];
  bookings: Owned<BookingRow>[] = [];
  notes = new Map<string, string>();
  private seq = 1;

  constructor(private readonly codes: () => string = () => `CODE${this.seq++}`.slice(0, 6).padEnd(6, 'X')) {}

  memberships(userId: string): Promise<Membership[]> {
    return Promise.resolve(this.members.filter((m) => m.userId === userId).flatMap((m) => {
      const f = this.families.find((x) => x.id === m.familyId);
      return f ? [{ familyId: f.id, familyName: f.name, inviteCode: f.inviteCode, callLink: f.callLink, groupCall: f.groupCall ?? null, memberId: m.id }] : [];
    }));
  }
  createFamily(name: string) {
    const family: Family = { id: `f${this.seq++}`, name, inviteCode: this.codes(), callLink: null };
    this.families = [...this.families, family];
    return Promise.resolve({ familyId: family.id, inviteCode: family.inviteCode });
  }
  familyByCode(code: string) {
    const f = this.families.find((x) => x.inviteCode === code);
    return Promise.resolve(f ? { familyId: f.id, familyName: f.name, memberCount: this.members.filter((m) => m.familyId === f.id).length } : null);
  }
  setCallLink(familyId: string, link: string | null) {
    this.families = this.families.map((f) => (f.id === familyId ? { ...f, callLink: link } : f));
    return Promise.resolve();
  }  startGroupCall(familyId: string, memberId: string, at: Date) {
    this.families = this.families.map((f) => (f.id === familyId ? { ...f, groupCall: { startedBy: memberId, at: at.toISOString() } } : f));
    return Promise.resolve();
  }

  setContact(userId: string, contact: Contact) {
    this.members = this.members.map((m) => (m.userId === userId ? { ...m, contact } : m));
    return Promise.resolve();
  }
  family(familyId: string): Db { return new MemoryFamily(this, familyId, () => `b${this.seq++}`); }
  leaveFamily(m: Membership) {
    const fid = m.familyId;
    this.members = this.members.filter((x) => x.id !== m.memberId);
    this.observations = this.observations.filter((x) => x.memberId !== m.memberId);
    this.blocks = this.blocks.filter((x) => x.memberId !== m.memberId);
    this.bookings = this.bookings.filter((x) => x.familyId !== fid || x.status !== 'proposed');
    if (this.members.some((x) => x.familyId === fid && !x.simulated)) return Promise.resolve();
    const gone = <T extends { familyId: string }>(xs: T[]) => xs.filter((x) => x.familyId !== fid);
    this.families = this.families.filter((f) => f.id !== fid);
    this.members = gone(this.members);
    this.observations = gone(this.observations);
    this.blocks = gone(this.blocks);
    this.bookings = gone(this.bookings);
    for (const k of [...this.notes.keys()]) if (k.startsWith(`${fid}|`)) this.notes.delete(k);
    return Promise.resolve();
  }
}

class MemoryFamily implements Db {
  constructor(private readonly d: MemoryDirectory, private readonly fid: string, private readonly nextId: () => string) {}
  private mine = <T extends { familyId: string }>(rows: T[]) => rows.filter((r) => r.familyId === this.fid);
  private others = <T extends { familyId: string }>(rows: T[]) => rows.filter((r) => r.familyId !== this.fid);

  load() {
    return Promise.resolve({
      members: this.mine(this.d.members), observations: this.mine(this.d.observations),
      blocks: this.mine(this.d.blocks), bookings: this.mine(this.d.bookings).filter((b) => b.status !== 'completed'),
    });
  }
  addMember(row: MemberRow & { userId: string | null }) {
    // Mirrors the database: one row per person per family (members_family_user_key).
    if (row.userId && this.d.members.some((m) => m.userId === row.userId && m.familyId === this.fid)) {
      return Promise.reject(new Error('user is already in this family'));
    }
    this.d.members = [...this.d.members, { ...row, familyId: this.fid }];
    return Promise.resolve();
  }
  addObservations(rows: readonly StoredObservation[]) {
    this.d.observations = [...this.d.observations, ...rows.map((r) => ({ ...r, familyId: this.fid }))];
    return Promise.resolve();
  }
  replaceBusyBlocks(memberId: string, blocks: readonly BusyBlock[], from: Date) {
    const ids = new Set(blocks.map((b) => b.id));
    const kept = this.d.blocks.filter((b) => b.familyId !== this.fid || b.memberId !== memberId || (b.end.getTime() <= from.getTime() && !ids.has(b.id)));
    this.d.blocks = [...kept, ...blocks.map((b) => ({ ...b, familyId: this.fid }))];
    return Promise.resolve();
  }
  dropBlocksBefore(cutoff: Date) {
    this.d.blocks = this.d.blocks.filter((b) => b.familyId !== this.fid || b.end.getTime() >= cutoff.getTime());
    return Promise.resolve();
  }
  findOpenBooking(start: Date) {
    return Promise.resolve(this.mine(this.d.bookings).find((b) => b.status !== 'completed' && b.start.getTime() === start.getTime()) ?? null);
  }
  createBooking(start: Date, levels: Record<string, Level>) {
    const row = { id: this.nextId(), start, durationMin: 45, acceptedBy: [], status: 'proposed' as const, levels, familyId: this.fid };
    this.d.bookings = [...this.d.bookings, row];
    return Promise.resolve(row);
  }
  acceptBooking(id: string, memberIds: readonly string[]) {
    const b = this.mine(this.d.bookings).find((x) => x.id === id && x.status !== 'completed');
    if (!b) return Promise.reject(new Error(`booking ${id} is not open`));
    const acceptedBy = [...new Set([...b.acceptedBy, ...memberIds])].sort();
    const status = acceptedBy.length >= this.mine(this.d.members).length ? 'booked' as const : b.status;
    const next = { ...b, acceptedBy, status };
    this.d.bookings = this.d.bookings.map((x) => (x.id === id ? next : x));
    return Promise.resolve(next);
  }
  setBurden(ledger: Ledger) {
    this.d.members = this.d.members.map((m) => (m.familyId === this.fid ? { ...m, burdenMin: ledger[m.id] ?? m.burdenMin } : m));
    return Promise.resolve();
  }
  clearHistory() {
    this.d.observations = this.others(this.d.observations);
    this.d.blocks = this.others(this.d.blocks);
    this.d.bookings = this.others(this.d.bookings);
    this.d.members = this.d.members
      .filter((m) => m.familyId !== this.fid || !m.simulated)
      .map((m) => (m.familyId === this.fid ? { ...m, burdenMin: 0 } : m));
    for (const k of [...this.d.notes.keys()]) if (k.startsWith(`${this.fid}|`)) this.d.notes.delete(k);
    return Promise.resolve();
  }
  getNote(key: string) { return Promise.resolve(this.d.notes.get(`${this.fid}|${key}`) ?? null); }
  putNote(key: string, text: string) { this.d.notes.set(`${this.fid}|${key}`, text); return Promise.resolve(); }
}
