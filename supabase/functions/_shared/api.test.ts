import { beforeEach, describe, expect, test } from 'bun:test';
import { ApiError, handle, MAX_FAMILIES, type ApiResult, type Caller, type Deps } from './api.ts';
import { MemoryDirectory } from './memoryDb.ts';
import { templateNote, type NoteWriter } from './notes.ts';

const NOW = new Date('2030-01-07T23:00:00Z');          // Mon 6 PM in New York
const later = (min: number) => new Date(NOW.getTime() + min * 60_000);
const ALICE: Caller = { userId: 'u-alice', email: 'alice@example.com' };
const BOB: Caller = { userId: 'u-bob', email: 'bob@example.com' };
const CAROL: Caller = { userId: 'u-carol', email: 'carol@example.com' };
const PROFILE = { name: 'Alice', tz: 'America/New_York', city: 'Durham', wake: '07:00', bed: '23:30', busy: [['09:00', '17:00']] };

let dir: MemoryDirectory;
let deps: Deps;
let ids = 0;

const call = (body: unknown, who: Caller = ALICE, at = NOW) => handle(body, who, deps, at);
async function fails(body: unknown, status: number, who: Caller = ALICE) {
  const err = await call(body, who).then(() => null, (e) => e);
  expect(err).toBeInstanceOf(ApiError);
  expect((err as ApiError).status).toBe(status);
}
const state = (r: ApiResult) => r.state!;

beforeEach(() => {
  let codes = 0;
  dir = new MemoryDirectory(() => ['KQ7MZ2', 'PX4HW9', 'TT3RRA'][codes++]!);
  ids = 0;
  deps = { dir, newId: () => `m${++ids}`, inviteCode: () => 'UNUSED' };
});

describe('accounts', () => {
  test('a new user has no family yet', async () => {
    const r = await call({ action: 'me' });
    expect(r.account).toBeNull();
    expect(r.state).toBeNull();
    await fails({ action: 'state' }, 409);
  });

  test('create_family makes you its first member with an invite code', async () => {
    const r = await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    expect(r.account).toMatchObject({ email: 'alice@example.com', familyName: 'Kims', inviteCode: 'KQ7MZ2' });
    expect(state(r).members.map((m) => m.name)).toEqual(['Alice']);
    expect(state(r).members[0]!.week).toHaveLength(96);
  });

  test('one account can be in several families and switch with family_id', async () => {
    const kims = await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    await call({ action: 'create_family', family_name: 'Parks', ...PROFILE, name: 'Carol' }, CAROL);
    const parks = await call({ action: 'join_family', invite_code: 'PX4HW9', name: 'Alice', tz: 'America/New_York' });
    expect(parks.account!.familyName).toBe('Parks');
    expect(parks.account!.families.map((f) => f.familyName)).toEqual(['Kims', 'Parks']);
    expect(state(parks).members.map((m) => m.name).sort()).toEqual(['Alice', 'Carol']);

    const back = await call({ action: 'state', family_id: kims.account!.familyId });
    expect(back.account!.familyName).toBe('Kims');
    expect(state(back).members.map((m) => m.name)).toEqual(['Alice']);
    // No family_id (or one you aren't in): your first family.
    expect((await call({ action: 'state' })).account!.familyName).toBe('Kims');
    expect((await call({ action: 'state', family_id: 'not-mine' })).account!.familyName).toBe('Kims');

    await fails({ action: 'join_family', invite_code: 'KQ7MZ2', name: 'Alice', tz: 'UTC' }, 409);
  });

  test('at most MAX_FAMILIES per account', async () => {
    let n = 0;
    const many = new MemoryDirectory(() => ['A2A2A2', 'B3B3B3', 'C4C4C4', 'D5D5D5', 'E6E6E6', 'F7F7F7'][n++]!);
    deps = { ...deps, dir: many };
    for (let i = 0; i < MAX_FAMILIES; i++) await call({ action: 'create_family', family_name: `F${i}`, ...PROFILE });
    await fails({ action: 'create_family', family_name: 'One more', ...PROFILE }, 409);
  });

  test('leaving one family opens your next one', async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    const parks = await call({ action: 'create_family', family_name: 'Parks', ...PROFILE });
    const left = await call({ action: 'leave_family', family_id: parks.account!.familyId });
    expect(left.account!.familyName).toBe('Kims');
    expect(left.account!.families.map((f) => f.familyName)).toEqual(['Kims']);
  });

  test('join_family by invite code; families never see each other', async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    const joined = await call({ action: 'join_family', invite_code: 'kq7mz2', name: 'Bob', tz: 'Asia/Seoul' }, BOB);
    expect(joined.account!.familyName).toBe('Kims');
    expect(state(joined).members.map((m) => m.name).sort()).toEqual(['Alice', 'Bob']);

    const other = await call({ action: 'create_family', family_name: 'Parks', ...PROFILE, name: 'Carol' }, CAROL);
    expect(state(other).members.map((m) => m.name)).toEqual(['Carol']);
    await fails({ action: 'join_family', invite_code: 'NOPE00', name: 'X', tz: 'UTC' }, 404, { userId: 'u-x', email: null });
  });

  test('each new family gets its own invite code', async () => {
    const a = await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    const c = await call({ action: 'create_family', family_name: 'Parks', ...PROFILE, name: 'Carol' }, CAROL);
    expect(a.account!.inviteCode).not.toBe(c.account!.inviteCode);
  });

  test('leave_family: you leave, the rest of the family stays', async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    await call({ action: 'join_family', invite_code: 'KQ7MZ2', name: 'Bob', tz: 'Asia/Seoul' }, BOB);
    await call({ action: 'log_outcome', member_id: 'm2', kind: 'label', free: true }, BOB);
    expect(dir.observations.filter((o) => o.memberId === 'm2').length).toBeGreaterThan(0);

    const left = await call({ action: 'leave_family' }, BOB);
    expect(left.account).toBeNull();
    expect((await call({ action: 'me' }, BOB)).account).toBeNull();
    await fails({ action: 'state' }, 409, BOB);

    const alice = await call({ action: 'state' });
    expect(state(alice).members.map((m) => m.name)).toEqual(['Alice']);
    expect(dir.observations.filter((o) => o.memberId === 'm2')).toHaveLength(0);

    // Bob can come back with the same code.
    const back = await call({ action: 'join_family', invite_code: 'KQ7MZ2', name: 'Bob', tz: 'Asia/Seoul' }, BOB);
    expect(state(back).members.map((m) => m.name).sort()).toEqual(['Alice', 'Bob']);
  });

  test('leave_family: the last person to leave deletes the family and its code', async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    await call({ action: 'add_demo_family' });
    await call({ action: 'leave_family' });
    expect(dir.families).toHaveLength(0);
    expect(dir.members).toHaveLength(0);
    await fails({ action: 'join_family', invite_code: 'KQ7MZ2', name: 'Bob', tz: 'UTC' }, 404, BOB);

    // Alice can start a new family, with a new code.
    const again = await call({ action: 'create_family', family_name: 'New Kims', ...PROFILE });
    expect(again.account!.inviteCode).toBe('PX4HW9');
  });

  test('set_call_link: one shared link per family, only known call services', async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    await call({ action: 'join_family', invite_code: 'KQ7MZ2', name: 'Bob', tz: 'Asia/Seoul' }, BOB);
    const link = 'https://facetime.apple.com/join#v=1&p=abc&k=def';
    const set = await call({ action: 'set_call_link', link }, BOB);
    expect(set.account!.callLink).toBe(link);
    expect((await call({ action: 'state' })).account!.callLink).toBe(link);

    await call({ action: 'set_call_link', link: 'https://us02web.zoom.us/j/123' });
    await fails({ action: 'set_call_link', link: 'http://facetime.apple.com/join' }, 400);
    await fails({ action: 'set_call_link', link: 'https://facetime.apple.com.evil.example/join' }, 400);
    await fails({ action: 'set_call_link', link: 'not a link' }, 400);

    const cleared = await call({ action: 'set_call_link', link: null });
    expect(cleared.account!.callLink).toBeNull();
    expect(cleared.account!.families[0]!.callLink).toBeNull();
  });

  test('phone and call apps: set at sign-up, shared with the family, same on every family', async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE, phone: '+1 (919) 555-0123' });
    const bob = await call({ action: 'join_family', invite_code: 'KQ7MZ2', name: 'Bob', tz: 'Asia/Seoul', phone: '+82 10 1234 5678' }, BOB);
    const seen = bob.state!.members.find((m) => m.name !== 'Bob')!;
    expect(seen.phone).toBe('+19195550123');

    await call({ action: 'create_family', family_name: 'Parks', ...PROFILE });
    await call({ action: 'set_contact', phone: '+19195550199', apps: { whatsapp: '+19195550199', wechat: 'kim_w' } });
    const again = await call({ action: 'state' }, BOB);
    const me = again.state!.members.find((m) => m.name !== 'Bob')!;
    expect(me.phone).toBe('+19195550199');
    expect(me.apps).toEqual({ whatsapp: '+19195550199', wechat: 'kim_w' });

    await fails({ action: 'set_contact', phone: '919-555-0123' }, 400);          // no country code
    await fails({ action: 'set_contact', apps: { snapchat: 'x' } }, 400);
    await fails({ action: 'set_contact' }, 400);
  });

  test('start_group_call shows everyone a Join for 45 minutes', async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    await call({ action: 'join_family', invite_code: 'KQ7MZ2', name: 'Bob', tz: 'Asia/Seoul' }, BOB);
    await fails({ action: 'start_group_call' }, 409);   // no link yet
    await call({ action: 'set_call_link', link: 'https://facetime.apple.com/join#v=1&p=abc' });
    const started = await call({ action: 'start_group_call' });
    const me = started.account!.memberId;
    expect(started.account!.groupCall!.startedBy).toBe(me);
    expect((await call({ action: 'state' }, BOB)).account!.groupCall!.startedBy).toBe(me);
  });

  test('set_call_link changes only the open family', async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    const parks = await call({ action: 'create_family', family_name: 'Parks', ...PROFILE });
    const parksId = parks.account!.familyId;
    await call({ action: 'set_call_link', family_id: parksId, link: 'https://meet.google.com/abc-defg-hij' });
    const fams = (await call({ action: 'me' })).account!.families;
    expect(fams.find((f) => f.familyId === parksId)!.callLink).toBe('https://meet.google.com/abc-defg-hij');
    expect(fams.find((f) => f.familyId !== parksId)!.callLink).toBeNull();
  });

  test('leave_family needs a family', async () => {
    await fails({ action: 'leave_family' }, 409);
  });

  test('profile is validated', async () => {
    await fails({ action: 'create_family', family_name: 'K', name: 'A', tz: 'Mars/Base' }, 400);
    await fails({ action: 'create_family', family_name: 'K', name: '', tz: 'UTC' }, 400);
    await fails({ action: 'create_family', family_name: 'K', name: 'A', tz: 'UTC', wake: '7am' }, 400);
  });
});

describe('demo family', () => {
  beforeEach(async () => { await call({ action: 'create_family', family_name: 'Kims', ...PROFILE }); });

  test('adds Mom, Grandpa and Dad as simulated relatives with two weeks of history', async () => {
    const s = state(await call({ action: 'add_demo_family' }));
    expect(s.members.map((m) => m.name).sort()).toEqual(['Alice', 'Dad', 'Grandpa', 'Mom']);
    expect(s.members.filter((m) => m.simulated).length).toBe(3);
    for (const m of s.members) {
      expect(m.levels).toHaveLength(48);
      expect(m.signals).toBeGreaterThan(50);
    }
    expect(s.suggestion).not.toBeNull();
    expect(s.note).toBeTruthy();
    expect(s.lastChange).toBeNull();                 // seeded history is not "a change"
  });

  test('is repeatable: adding again replaces the relatives', async () => {
    await call({ action: 'add_demo_family' });
    const s = state(await call({ action: 'add_demo_family' }));
    expect(s.members).toHaveLength(4);
  });

  test('simulate drives a relative and reports which cells the AI changed', async () => {
    const s0 = state(await call({ action: 'add_demo_family' }));
    const mom = s0.members.find((m) => m.name === 'Mom')!;
    let s = s0;
    for (let i = 0; i < 4; i++) s = state(await call({ action: 'simulate', member_id: mom.id, event: 'busy' }, ALICE, later(i)));
    expect(s.lastChange).toMatchObject({ memberId: mom.id, source: 'sim', kind: 'label', positive: false });
    const momNow = s.members.find((m) => m.id === mom.id)!;
    expect(momNow.signals).toBe(mom.signals + 4);
  });

  test('only simulated relatives can be driven', async () => {
    const s = state(await call({ action: 'add_demo_family' }));
    const me = s.members.find((m) => !m.simulated)!;
    await fails({ action: 'simulate', member_id: me.id, event: 'busy' }, 403);
    await fails({ action: 'simulate', member_id: 'ghost', event: 'busy' }, 404);
  });

  test('reset_family removes simulated relatives and history', async () => {
    await call({ action: 'add_demo_family' });
    const s = state(await call({ action: 'reset_family' }));
    expect(s.members.map((m) => m.name)).toEqual(['Alice']);
    expect(s.members[0]!.signals).toBe(0);
  });
});

describe('signals', () => {
  let momId = '';
  beforeEach(async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    momId = state(await call({ action: 'add_demo_family' })).members.find((m) => m.name === 'Mom')!.id;
  });

  test('a call you placed counts for them, and for you (you were free to call)', async () => {
    const before = dir.observations.length;
    await call({ action: 'log_outcome', member_id: momId, kind: 'call', answered: true, source: 'family_call' });
    await call({ action: 'log_outcome', member_id: momId, kind: 'text', reply_seconds: 30, source: 'shortcut' });
    await call({ action: 'log_outcome', kind: 'label', free: false, source: 'widget' });
    expect(dir.observations.length).toBe(before + 4);
    const mine = dir.observations.slice(before).filter((o) => o.memberId !== momId);
    expect(mine.some((o) => o.outcome.kind === 'call' && o.outcome.answered)).toBe(true);
  });

  test('never accepts message content, future times, other people\'s labels or strangers', async () => {
    await fails({ action: 'log_outcome', member_id: momId, kind: 'text', reply_seconds: 5, text: 'hi' }, 400);
    await fails({ action: 'log_outcome', member_id: momId, kind: 'text', reply_seconds: 5, body: 'hi' }, 400);
    await fails({ action: 'log_outcome', member_id: momId, kind: 'call', answered: true, at: '2099-01-01T00:00:00Z' }, 400);
    await fails({ action: 'log_outcome', member_id: momId, kind: 'label', free: true }, 403);
    await fails({ action: 'log_outcome', member_id: momId, kind: 'label', free: true, source: 'sim' }, 400);
    await call({ action: 'create_family', family_name: 'Parks', ...PROFILE, name: 'Carol' }, CAROL);
    await fails({ action: 'log_outcome', member_id: momId, kind: 'call', answered: true }, 404, CAROL);
  });

  test('push_busy turns your calendar time red and only touches your blocks', async () => {
    const s0 = state(await call({ action: 'state' }));
    const mine = (s: typeof s0) => s.members.find((m) => !m.simulated)!.levels;
    const slot = mine(s0).findIndex((l) => l !== 'R');
    const start = new Date(new Date(s0.forecastStart).getTime() + slot * 1_800_000);
    const s = state(await call({ action: 'push_busy', blocks: [
      { id: 'cal-1', start: start.toISOString(), end: new Date(start.getTime() + 3_600_000).toISOString(), movable: true },
    ] }));
    expect(mine(s)[slot]).toBe('R');
    await fails({ action: 'push_busy', blocks: [{ id: 'x', start: start.toISOString(), end: start.toISOString() }] }, 400);
    await fails({ action: 'push_busy', blocks: Array(201).fill({}) }, 400);
  });
});

describe('join', () => {
  const START = '2030-01-08T01:00:00Z';

  test('with simulated relatives, your tap books it and charges the ledger once', async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    await call({ action: 'add_demo_family' });
    const r = await call({ action: 'join', start: START });
    expect(r.booking!.status).toBe('booked');
    const burden = dir.members.map((m) => m.burdenMin);
    await call({ action: 'join', start: START });
    expect(dir.members.map((m) => m.burdenMin)).toEqual(burden);
  });

  test('with two real people, it waits for both', async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    await call({ action: 'join_family', invite_code: 'KQ7MZ2', name: 'Bob', tz: 'Asia/Seoul' }, BOB);
    expect((await call({ action: 'join', start: START })).booking!.status).toBe('proposed');
    expect((await call({ action: 'join', start: START }, BOB)).booking!.status).toBe('booked');
  });

  test('rejects off-grid, past and far-future times', async () => {
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    await fails({ action: 'join', start: '2030-01-08T01:10:00Z' }, 400);
    await fails({ action: 'join', start: '2030-01-01T00:00:00Z' }, 409);
    await fails({ action: 'join', start: '2030-03-01T00:00:00Z' }, 400);
  });
});

describe('AI note', () => {
  test('uses the writer once per suggestion and falls back when it fails', async () => {
    let calls = 0;
    const writer: NoteWriter = { write: async () => { calls++; return 'Claude says hi.'; } };
    deps = { ...deps, notes: writer };
    await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
    const a = state(await call({ action: 'add_demo_family' }));
    const b = state(await call({ action: 'state' }));
    expect(a.note).toBe('Claude says hi.');
    expect(b.note).toBe('Claude says hi.');
    expect(calls).toBe(1);

    deps = { ...deps, notes: { write: () => Promise.reject(new Error('down')) } };
    await call({ action: 'reset_family' });
    const c = state(await call({ action: 'add_demo_family' }));
    expect(c.note).not.toBe('Claude says hi.');
    expect(c.note).toContain('for you');
  });

  test('template names local times', () => {
    const text = templateNote({ viewer: 'Alice', everyoneLikely: true, latestSignal: null, people: [
      { name: 'Alice', localTime: 'Mon 8:00 PM', pickupPercent: 80, isViewer: true },
      { name: 'Mom', localTime: 'Tue 10:00 AM', pickupPercent: 75, isViewer: false },
    ] });
    expect(text).toBe('8:00 PM for you, 10:00 AM for Mom. Everyone usually picks up then.');
  });
});

test('unknown actions and bad bodies are 400', async () => {
  await call({ action: 'create_family', family_name: 'Kims', ...PROFILE });
  await fails({ action: 'drop_tables' }, 400);
  await fails(null, 400);
  await fails([], 400);
});
