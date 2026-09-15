import {BridgeState} from '../typetune-session@typetune.local/state.js';
const assert = (value, message) => { if (!value) throw new Error(message); };
const state = new BridgeState('11111111-1111-4111-8111-111111111111');
const a = {}, b = {};
const input = {source: {type: 'xkb', id: 'us', xkbId: 'us'},
    window: a, windowBackend: 'wayland', locked: false, shieldActive: false,
    overview: false, userSession: true, externalSource: false};
const first = state.snapshot(input);
state.invalidate(); input.window = b;
assert(state.snapshot(input).window !== first.window, 'focus must have a distinct token');
state.invalidate(); input.window = a;
assert(state.snapshot(input).window === first.window, 'same window token');
assert(state.snapshot(input).generation > first.generation, 'A-B-A must invalidate');
state.invalidate(true); input.source.id = 'ru'; input.source.xkbId = 'ru';
assert(state.snapshot(input).source_generation > first.source_generation, 'source generation');
assert(state.snapshot(input).source_id === 'ru', 'live source');
for (const key of ['locked', 'shieldActive', 'overview']) {
    input[key] = true;
    const snapshot = state.snapshot(input);
    assert(snapshot.window === 0 && snapshot.source_id === '', 'restricted state redaction');
    input[key] = false;
}
input.userSession = false;
assert(state.snapshot(input).window === 0, 'non-user mode');
input.userSession = true; input.externalSource = true;
assert(state.snapshot(input).source_id === '', 'external keymap cannot use currentSource');
const restarted = new BridgeState('22222222-2222-4222-8222-222222222222');
assert(restarted.snapshot(input).instance !== first.instance, 'reload instance');
print('PASS BRIDGE-JS: focus A-B-A, source generation, lock/overview redaction, external map, reload');

const {sourceRequest} = await import('../typetune-session@typetune.local/state.js');
const current = {...first};
const request = {instance: current.instance, generation: current.generation,
    window: current.window, target: 'ru'};
assert(sourceRequest(request, current) === null, 'current request accepted');
for (const key of ['generation', 'window'])
    assert(sourceRequest({...request, [key]: request[key] + 1}, current) === 'changed', key);
assert(sourceRequest({...request, instance: 'old'}, current) === 'changed', 'old instance');
for (const key of ['locked', 'shield_active', 'overview', 'external_source'])
    assert(sourceRequest(request, {...current, [key]: true}) === 'context', key);
assert(sourceRequest(request, {...current, user_session: false}) === 'context', 'session');
assert(sourceRequest({...request, target: 'de'}, current) === 'invalid_request', 'target');
assert(sourceRequest({...request, extra: 1}, current) === 'invalid_request', 'schema');
assert(sourceRequest(request, {...current, source_type: 'ibus'}) === 'context', 'IME source');
print('PASS SWITCH-JS: schema, stale generation/window/instance, lock/overview/session/external/IME guards');
