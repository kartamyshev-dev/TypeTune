// Pure protocol state, shared by Shell integration and deterministic GJS tests.
// Window tokens are scoped to this enable() instance; no titles/app text.
export class BridgeState {
    constructor(instance) {
        this.instance = instance;
        this.generation = 1;
        this.sourceGeneration = 1;
        this._windows = new WeakMap();
        this._nextWindow = 1;
    }

    invalidate(sourceChanged = false) {
        if (++this.generation > Number.MAX_SAFE_INTEGER)
            throw new Error('Bridge generation exhausted');
        if (sourceChanged)
            this.sourceGeneration++;
    }

    snapshot(input) {
        const restricted = input.locked || input.shieldActive || input.overview || !input.userSession;
        const source = restricted || input.externalSource ? null : input.source;
        let window = 0;
        if (!restricted && input.window) {
            if (!this._windows.has(input.window))
                this._windows.set(input.window, this._nextWindow++);
            window = this._windows.get(input.window);
        }
        const clean = value => typeof value === 'string' &&
            /^[a-zA-Z0-9_+.:@/-]{1,128}$/.test(value) ? value : '';
        return {
            protocol: 1,
            instance: this.instance,
            generation: this.generation,
            source_generation: this.sourceGeneration,
            source_type: source && ['xkb', 'ibus'].includes(source.type) ? source.type : '',
            source_id: clean(source?.id),
            xkb_id: clean(source?.xkbId),
            window,
            window_backend: window ? input.windowBackend : 'unknown',
            locked: input.locked,
            shield_active: input.shieldActive,
            overview: input.overview,
            user_session: input.userSession,
            external_source: input.externalSource,
        };
    }
}

// Validate an explicit layout request against a freshly obtained snapshot.
export function sourceRequest(request, current) {
    if (!request || typeof request !== 'object' || Array.isArray(request) ||
        Object.keys(request).sort().join(',') !== 'generation,instance,target,window' ||
        !['us', 'ru'].includes(request.target) ||
        !Number.isSafeInteger(request.generation) || !Number.isSafeInteger(request.window))
        return 'invalid_request';
    if (current.locked || current.shield_active || current.overview ||
        !current.user_session || current.external_source || current.window === 0 ||
        current.source_type !== 'xkb' || !['us', 'ru'].includes(current.source_id))
        return 'context';
    if (request.instance !== current.instance || request.generation !== current.generation ||
        request.window !== current.window)
        return 'changed';
    return null;
}
