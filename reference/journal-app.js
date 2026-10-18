(() => {
  function initializeDeepWork(readOnly = false) {
    const root = document.getElementById('deep-work-repaired-concept');
    if (!root || root.dataset.deepWorkInitialized === 'true') return;
    root.dataset.deepWorkInitialized = 'true';
    const el = id => root.querySelector('#' + id);
    const R = window.DeepWorkReports;
    const MINUTE = 60000;
    const STORAGE_KEY = 'deep-work-journal-v1';
    const SETTINGS_KEY = 'deep-work-settings-v1';
    const views = ['focus','journal','settings'];
    const setup = el('dw-setup'), running = el('dw-running');
    const setupActions = el('dw-setup-actions'), runningActions = el('dw-running-actions');
    const appWindow = el('dw-window'), repeatInput = el('dw-repeat');
    const focusSelect = el('dw-focus-select'), breakSelect = el('dw-break-select');
    const focusInput = el('dw-focus-custom'), breakInput = el('dw-break-custom');
    const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    const announce = message => { el('dw-announcement').textContent = message; };
    const uid = () => typeof crypto.randomUUID === 'function' ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2);
    const validTimestamp = n => Number.isFinite(n) && Math.abs(n) < 8640000000000000;
    let storageAvailable = true, storageMessage = 'Saved on this device', lastSavedAt = 0;
    let saved = null;
    try { const raw = localStorage.getItem(STORAGE_KEY); if (raw) saved = JSON.parse(raw); }
    catch (error) { storageAvailable = false; storageMessage = 'Saving unavailable · export your journal to keep it'; }
    function cleanRecord(record) {
      if (!record || typeof record.id !== 'string' || !validTimestamp(record.start) || !validTimestamp(record.end) || record.end < record.start || !Number.isFinite(record.plannedMs) || record.plannedMs <= 0 || !Array.isArray(record.segments)) return null;
      const segments = record.segments.filter(s => s && validTimestamp(s.start) && validTimestamp(s.end) && s.end >= s.start && s.start >= record.start && s.end <= record.end).map(s => ({start:s.start,end:s.end}));
      return {id:record.id,start:record.start,end:record.end,plannedMs:record.plannedMs,status:record.status === 'complete' ? 'complete' : 'partial',segments};
    }
    let records = Array.isArray(saved?.records) ? saved.records.map(cleanRecord).filter(Boolean) : [];
    const defaultSchedule = {mode:'weekdays',weekdays:[1,2,3,4,5],on:2,off:2,anchor:R.localKey(Date.now()),weekStart:1,cutoff:0};
    let schedule = {...defaultSchedule};
    if (saved?.schedule && ['weekdays','everyday','shifts'].includes(saved.schedule.mode)) {
      const s = saved.schedule;
      schedule = {...defaultSchedule,...s,weekdays:Array.isArray(s.weekdays) ? s.weekdays.filter(n => Number.isInteger(n) && n >= 0 && n <= 6) : defaultSchedule.weekdays};
      if (!Number.isInteger(schedule.weekStart) || schedule.weekStart < 0 || schedule.weekStart > 6) schedule.weekStart = 1;
      if (!Number.isInteger(schedule.cutoff) || schedule.cutoff < 0 || schedule.cutoff > 1439) schedule.cutoff = 0;
      for (const k of ['on','off']) if (!Number.isInteger(schedule[k]) || schedule[k] < 1 || schedule[k] > 31) schedule[k] = 2;
      try { R.dateAt(schedule.anchor); } catch (_) { schedule.anchor = defaultSchedule.anchor; }
    }
    let phase = 'setup', paused = false, done = false, restored = false;
    let passiveCycle = readOnly && saved?.active?.phase === 'focus' ? cleanRecord(saved.active.currentCycle) : null;
    let focusMinutes = 60, breakMinutes = 10, totalMs = 0, remainingMs = 0, deadline = 0, ticker = null;
    let currentCycle = null, repeating = saved?.preferences?.repeating ?? true;
    let view = 'journal', period = 'week', sampleMode = records.length === 0 && !saved?.active;
    let reportDate = R.dayKey(Date.now(),schedule.cutoff), pageNumber = 0, currentReport = null;
    let currentBounds = null, lastJournalPaint = 0, lastSettingsPaint = 0, sampleRecords = [];
    let settingsStorageAvailable = true;
    let appSettings = {launchAtLogin:false,feedbackDraft:{type:'general',email:'',message:''}};
    try {
      const storedSettings = JSON.parse(localStorage.getItem(SETTINGS_KEY) || 'null');
      if (storedSettings) {
        appSettings.launchAtLogin = storedSettings.launchAtLogin === true;
        const draft = storedSettings.feedbackDraft;
        if (draft && typeof draft === 'object') appSettings.feedbackDraft = {
          type:['idea','problem','general'].includes(draft.type) ? draft.type : 'general',
          email:typeof draft.email === 'string' ? draft.email.slice(0,254) : '',
          message:typeof draft.message === 'string' ? draft.message.slice(0,5000) : ''
        };
      }
    } catch (_) { settingsStorageAvailable = false; }
    const pageSize = 12;
    repeatInput.checked = repeating;
    if (saved?.preferences) {
      const p = saved.preferences;
      if (['60','90','custom'].includes(p.focusChoice)) focusSelect.value = p.focusChoice;
      if (['10','20','custom'].includes(p.breakChoice)) breakSelect.value = p.breakChoice;
      if (Number.isInteger(p.focusCustom) && p.focusCustom >= 1 && p.focusCustom <= 480) focusInput.value = p.focusCustom;
      if (Number.isInteger(p.breakCustom) && p.breakCustom >= 1 && p.breakCustom <= 480) breakInput.value = p.breakCustom;
    }
    const a = saved?.active;
    if (!readOnly && a && ['focus','break'].includes(a.phase) && Number.isInteger(a.focusMinutes) && a.focusMinutes >= 1 && a.focusMinutes <= 480 && Number.isInteger(a.breakMinutes) && a.breakMinutes >= 1 && a.breakMinutes <= 480 && Number.isFinite(a.remainingMs) && a.remainingMs > 0) {
      phase = a.phase; focusMinutes = a.focusMinutes; breakMinutes = a.breakMinutes;
      totalMs = (phase === 'focus' ? focusMinutes : breakMinutes) * MINUTE;
      remainingMs = Math.min(a.remainingMs,totalMs); paused = true; restored = true;
      if (phase === 'focus') {
        const recovered = cleanRecord(a.currentCycle);
        if (recovered && !records.some(r => r.id === recovered.id)) currentCycle = {...recovered,openStart:null};
        else { phase = 'setup'; paused = false; restored = false; remainingMs = 0; }
      }
    }

    function paintStorage() { el('dw-storage-status').textContent = storageMessage; }
    function mergeRecords(external) {
      const index = new Map(records.map(r => [r.id,r]));
      for (const candidate of external) {
        const record = cleanRecord(candidate); if (!record) continue;
        const old = index.get(record.id);
        if (!old || (old.status !== 'complete' && record.status === 'complete') || (old.status === record.status && record.end > old.end)) index.set(record.id,record);
      }
      records = [...index.values()];
    }
    function projectedCycle(now) {
      if (!currentCycle) return null;
      const segments = currentCycle.segments.map(s => ({...s}));
      if (currentCycle.openStart !== null) {
        const end = Math.max(currentCycle.openStart,Math.min(now,deadline));
        if (end > currentCycle.openStart) segments.push({start:currentCycle.openStart,end});
      }
      return {id:currentCycle.id,start:currentCycle.start,end:now,plannedMs:currentCycle.plannedMs,status:'live',segments};
    }
    function persist(now = Date.now()) {
      if (!storageAvailable) return;
      try {
        const external = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null');
        if (Array.isArray(external?.records)) mergeRecords(external.records);
        const active = readOnly ? external?.active ?? null : phase === 'setup' || done ? null : {phase,focusMinutes,breakMinutes,remainingMs:paused ? remainingMs : Math.max(0,deadline-now),currentCycle:projectedCycle(now),savedAt:now};
        localStorage.setItem(STORAGE_KEY,JSON.stringify({version:1,records,schedule,active,preferences:{repeating,focusChoice:focusSelect.value,breakChoice:breakSelect.value,focusCustom:focusInput.valueAsNumber,breakCustom:breakInput.valueAsNumber}}));
        lastSavedAt = now;
      } catch (_) { storageAvailable = false; storageMessage = 'Saving unavailable · export your journal to keep it'; paintStorage(); }
    }
    function sealSegment(at) {
      if (!currentCycle || currentCycle.openStart === null) return;
      const end = Math.max(currentCycle.openStart,at);
      if (end > currentCycle.openStart) currentCycle.segments.push({start:currentCycle.openStart,end});
      currentCycle.openStart = null;
    }
    function finalizeFocus(at,status) {
      if (!currentCycle) return;
      sealSegment(at);
      const record = {id:currentCycle.id,start:currentCycle.start,end:at,plannedMs:currentCycle.plannedMs,status,segments:currentCycle.segments.map(s => ({...s}))};
      if (record.segments.some(s => s.end > s.start)) {
        const index = records.findIndex(r => r.id === record.id);
        if (index < 0) records.push(record); else records[index] = record;
      }
      currentCycle = null;
    }
    const readMinutes = (select,input) => {
      if (!select.value) return null;
      const n = select.value === 'custom' ? input.valueAsNumber : Number(select.value);
      return Number.isInteger(n) && n >= 1 && n <= 480 ? n : null;
    };
    function updateSetup() {
      for (const [kind,select,input] of [['focus',focusSelect,focusInput],['break',breakSelect,breakInput]]) {
        const custom = select.value === 'custom', valid = readMinutes(select,input) !== null;
        el(`dw-${kind}-custom-row`).hidden = !custom; input.disabled = !custom || readOnly; select.disabled = readOnly;
        el(`dw-${kind}-error`).hidden = !custom || valid; input.setAttribute('aria-invalid',String(custom && !valid));
      }
      const focus = readMinutes(focusSelect,focusInput), rest = readMinutes(breakSelect,breakInput);
      el('dw-start').disabled = readOnly || focus === null || rest === null;
      repeatInput.disabled = readOnly;
      el('dw-summary').textContent = focus !== null && rest !== null ? `${focus} min deep  →  ${rest} min break` : 'Choose both durations to begin.';
      paintRepeat();
    }
    function paintRepeat() {
      el('dw-repeat-note').textContent = phase === 'setup' ? repeating ? 'Deep work, then break. Repeat until unchecked.' : 'One deep work cycle and one break, then stop.' : done ? repeating ? 'Your next session will repeat.' : 'Session complete. Repeat is off.' : repeating ? 'Deep work, then break. Repeat until unchecked.' : phase === 'focus' ? 'Stops after your upcoming break.' : 'Stops after this break.';
    }
    function updateSlack() {
      const statusRestored = phase === 'break' || done;
      el('dw-status-cross').hidden = statusRestored; el('dw-status-restored').hidden = !statusRestored;
      el('dw-slack-text').textContent = statusRestored ? 'Previous status restored' : 'Deep WORK, DND';
      el('dw-slack-note').textContent = phase === 'setup' ? 'Set during focus. Previous status restored on break.' : done ? 'Session finished. Your previous status is restored.' : statusRestored ? repeating ? 'Deep work status returns with the next focus cycle.' : 'Your previous status stays in place after this break.' : paused ? 'Focus status stays in place while the timer is paused.' : 'Focus status clears when your focus cycle ends.';
    }
    function paintTimer() {
      const seconds = Math.max(0,Math.ceil(remainingMs/1000));
      const time = `${String(Math.floor(seconds/60)).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}`;
      el('dw-timer').textContent = time;
      const percent = totalMs > 0 ? Math.max(0,Math.min(100,(1-remainingMs/totalMs)*100)) : 0;
      el('dw-progress-fill').style.width = percent + '%'; el('dw-progress').setAttribute('aria-valuenow',String(Math.round(percent)));
      const idle = phase === 'setup' || done;
      const label = idle ? 'Deep Work' : `${time} - ${phase === 'focus' ? 'deep' : 'break'}`;
      el('dw-menu-text').textContent = label; el('dw-menu-pause-icon').hidden = !paused || idle; el('dw-menu-timer-icon').hidden = paused && !idle;
      el('dw-menu-status').setAttribute('aria-label',`${paused && !idle ? 'Paused. ' : ''}${label}. Show Deep Work window.`);
    }
    function paintPhase() {
      const focus = phase === 'focus', isSetup = phase === 'setup';
      setup.hidden = !isSetup; running.hidden = isSetup; setupActions.hidden = !isSetup; runningActions.hidden = isSetup;
      el('dw-recovery-note').hidden = !restored && !readOnly;
      el('dw-recovery-note').textContent = readOnly ? 'The timer is open in another preview. You can browse the journal here. Close the other preview and reload this one to use the timer here.' : 'Your unfinished session is paused at its last saved point. Resume when you’re ready.';
      el('dw-phase-name').textContent = done ? 'Cycle complete' : paused ? focus ? 'Deep work paused' : 'Break paused' : focus ? 'Deep work' : 'Take a break';
      el('dw-focus-icon').hidden = !focus; el('dw-break-icon').hidden = focus;
      el('dw-run-caption').textContent = done ? 'Saved to your journal.' : paused ? 'Paused time is excluded from your journal.' : focus ? `${breakMinutes}-minute break next` : repeating ? `${focusMinutes}-minute deep work next` : 'Your final break.';
      el('dw-pause').textContent = done ? 'Start again' : paused ? 'Resume' : 'Pause';
      el('dw-next').textContent = focus ? 'Take break' : repeating ? 'Skip break' : 'Finish break'; el('dw-next').hidden = done;
      paintRepeat(); updateSlack(); paintTimer();
    }
    function clearTicker() { if (ticker !== null) clearInterval(ticker); ticker = null; }
    function startTicker() { clearTicker(); ticker = setInterval(tick,250); }
    function enterPhase(nextPhase,at) {
      phase = nextPhase; paused = false; done = false; restored = false;
      totalMs = (phase === 'focus' ? focusMinutes : breakMinutes)*MINUTE;
      deadline = at+totalMs; remainingMs = totalMs;
      if (phase === 'focus') currentCycle = {id:uid(),start:at,plannedMs:totalMs,segments:[],openStart:at};
    }
    function finishPair() { clearTicker(); done = true; paused = false; restored = false; remainingMs = 0; }
    function reconcile(now = Date.now()) {
      if (phase === 'setup' || paused || done) return false;
      let crossed = false;
      while (now >= deadline && !done) {
        crossed = true;
        const boundary = deadline;
        if (phase === 'focus') { finalizeFocus(boundary,'complete'); enterPhase('break',boundary); }
        else if (repeating) enterPhase('focus',boundary);
        else finishPair();
      }
      if (!done) remainingMs = Math.max(0,deadline-now);
      return crossed;
    }
    function tick() {
      if (!root.isConnected) { clearTicker(); return; }
      const now = Date.now(), crossed = reconcile(now);
      if (crossed) { paintPhase(); persist(now); announce(done ? 'Focus and break complete. Session saved.' : phase === 'focus' ? 'Next deep work cycle started.' : 'Focus cycle saved. Break started.'); }
      else paintTimer();
      if (now-lastSavedAt >= 5000 && phase !== 'setup' && !done) persist(now);
      if (view === 'journal' && !appWindow.hidden && !el('dw-journal-report').hidden && now-lastJournalPaint >= 1000) renderJournal(now);
      if (view === 'settings' && !appWindow.hidden && now-lastSettingsPaint >= 1000) paintSettings(now);
    }
    function beginPhase(nextPhase,now = Date.now()) {
      enterPhase(nextPhase,now); sampleMode = false; paintPhase(); startTicker(); persist(now);
      announce(nextPhase === 'focus' ? `${focusMinutes} minutes of deep work started. Your journal is recording.` : 'Break started. Focus time saved to your journal.');
      if (!appWindow.hidden && view === 'focus') el('dw-pause').focus();
    }
    function setView(nextView,moveFocus = false) {
      const now = Date.now();
      if (reconcile(now)) { paintPhase(); persist(now); }
      view = nextView;
      for (const key of views) el('dw-'+key+'-panel').hidden = view !== key;
      appWindow.classList.toggle('dw-wide',view === 'journal');
      appWindow.classList.toggle('dw-settings-window',view === 'settings');
      for (const key of views) { el('dw-tab-'+key).setAttribute('aria-selected',String(key === view)); el('dw-tab-'+key).tabIndex = key === view ? 0 : -1; }
      if (view === 'journal') renderJournal(); else if (view === 'settings') paintSettings(now); else paintPhase();
      if (moveFocus) el('dw-tab-'+view).focus();
    }
    function duration(ms,precise = false) {
      const seconds = Math.max(0,Math.floor(ms/1000));
      const h = Math.floor(seconds/3600), m = Math.floor(seconds%3600/60), s = seconds%60;
      if (precise) return h ? `${h}h ${m}m${s ? ` ${s}s` : ''}` : m ? `${m}m${s ? ` ${s}s` : ''}` : `${s}s`;
      if (h) return m ? `${h}h ${m}m` : `${h}h`;
      if (m) return `${m}m`;
      return seconds ? `${seconds}s` : '0m';
    }
    const dateLabel = (at,options={month:'short',day:'numeric'}) => new Date(at).toLocaleDateString('en',options);
    const timeLabel = at => new Date(at).toLocaleTimeString('en-GB',{hour:'2-digit',minute:'2-digit'});
    const localDateTime = at => R.localKey(at)+'T'+timeLabel(at);
    function dateTimeValue(id) {
      const value = el(id).value; if (!value) return NaN;
      const at = new Date(value).getTime();
      return validTimestamp(at) && localDateTime(at) === value ? at : NaN;
    }
    function reportBounds() {
      if (period === 'range') {
        const from = dateTimeValue('dw-range-from'), to = dateTimeValue('dw-range-to');
        return {from,to,valid:Number.isFinite(from) && Number.isFinite(to) && to > from && to-from <= 3660*86400000};
      }
      try {
        const key = period === 'week' ? R.weekKey(reportDate,schedule.weekStart) : reportDate;
        return {from:R.dateAt(key,schedule.cutoff),to:R.dateAt(R.addDays(key,period === 'week' ? 7 : 1),schedule.cutoff),valid:true};
      } catch (_) { return {from:NaN,to:NaN,valid:false}; }
    }
    function actualRecords(now) {
      const live = readOnly && passiveCycle ? {...passiveCycle,status:'live'} : projectedCycle(now);
      return live ? records.filter(record=>record.id !== live.id).concat(live) : records;
    }
    function getRecords(now) { return sampleMode ? sampleRecords : actualRecords(now); }
    function makeSampleData() {
      const result = [], today = R.localKey(Date.now());
      for (let offset = -34; offset <= 0; offset++) {
        const key = R.addDays(today,offset), day = new Date(R.dateAt(key)).getDay();
        const count = [0,3,2,4,3,2,1][day];
        let next = R.dateAt(key,9*60+10);
        for (let i = 0; i < count; i++) {
          const plannedMs = (i%2 ? 90 : 60)*MINUTE;
          const partial = (day === 2 && i === count-1) || (day === 6);
          const actualMs = partial ? (day === 6 ? 35 : 25)*MINUTE : plannedMs;
          const pauseMs = i === 1 ? 10*MINUTE : 0;
          const end = next+actualMs+pauseMs;
          if (end <= Date.now()) {
            const segments = pauseMs ? [{start:next,end:next+actualMs/2},{start:next+actualMs/2+pauseMs,end}] : [{start:next,end}];
            result.push({id:`example-${key}-${i}`,start:next,end,plannedMs,status:partial?'partial':'complete',segments});
          }
          next = end+20*MINUTE;
        }
      }
      return result;
    }
    function scheduleSummary() {
      let days = schedule.mode === 'everyday' ? 'Any day' : schedule.mode === 'shifts' ? `${schedule.on} on / ${schedule.off} off` : schedule.weekdays.length === 7 ? 'Every day' : schedule.weekdays.join(',') === '1,2,3,4,5' ? 'Monday–Friday' : schedule.weekdays.length ? schedule.weekdays.map(d => dayNames[d].slice(0,3)).join(', ') : 'No fixed workdays';
      return `${days} · Week starts ${dayNames[schedule.weekStart]}${schedule.cutoff ? ' · Day starts '+String(Math.floor(schedule.cutoff/60)).padStart(2,'0')+':'+String(schedule.cutoff%60).padStart(2,'0') : ''}`;
    }
    function renderJournal(now = Date.now()) {
      lastJournalPaint = now;
      const crossed = reconcile(now); if (crossed) { paintPhase(); persist(now); }
      el('dw-schedule-summary').textContent = scheduleSummary();
      el('dw-sample-banner').hidden = !sampleMode;
      el('dw-toggle-sample').textContent = sampleMode ? 'Show my journal' : 'View example';
      el('dw-date-navigation').hidden = period === 'range'; el('dw-custom-range').hidden = period !== 'range';
      el('dw-report-date').value = reportDate;
      el('dw-previous-period').setAttribute('aria-label','Previous '+period); el('dw-next-period').setAttribute('aria-label','Next '+period);
      for (const button of root.querySelectorAll('[data-period]')) button.setAttribute('aria-pressed',String(button.dataset.period === period));
      const bounds = reportBounds(); currentBounds = bounds;
      el('dw-range-error').hidden = bounds.valid;
      el('dw-range-error').textContent = 'Choose valid local dates and an end time after the start, within a 10-year range.';
      el('dw-range-from').setAttribute('aria-invalid',String(!bounds.valid)); el('dw-range-to').setAttribute('aria-invalid',String(!bounds.valid));
      let grouping = el('dw-grouping').value;
      if (bounds.valid && bounds.to-bounds.from > 93*86400000 && grouping === 'day') { grouping = 'week'; el('dw-grouping').value = 'week'; }
      const report = R.buildReport(getRecords(now),bounds.valid ? bounds.from : NaN,bounds.valid ? bounds.to : NaN,schedule,grouping); currentReport = report;
      const startKey = bounds.valid ? R.dayKey(bounds.from,schedule.cutoff) : reportDate;
      const endKey = bounds.valid ? R.dayKey(bounds.to-1,schedule.cutoff) : reportDate;
      const today = R.dayKey(now,schedule.cutoff);
      el('dw-period-title').textContent = !bounds.valid ? 'Choose a valid range' : period === 'day' ? `${startKey === today ? 'Today · ' : ''}${dateLabel(bounds.from,{weekday:'short',month:'long',day:'numeric',year:'numeric'})}` : period === 'week' ? `${R.weekKey(today,schedule.weekStart) === startKey ? 'This week · ' : ''}${dateLabel(R.dateAt(startKey))} – ${dateLabel(R.dateAt(endKey),{month:'short',day:'numeric',year:'numeric'})}` : `${dateLabel(bounds.from)} ${timeLabel(bounds.from)} – ${dateLabel(bounds.to)} ${timeLabel(bounds.to)}`;
      el('dw-stat-time').textContent = duration(report.focusMs); el('dw-stat-time').title = duration(report.focusMs,true);
      el('dw-stat-cycles').textContent = report.cycles;
      el('dw-stat-cycle-note').textContent = `${report.rows.filter(r=>r.status === 'partial' && r.focusMs > 0).length} partial ${report.rows.filter(r=>r.status === 'partial' && r.focusMs > 0).length === 1 ? 'session' : 'sessions'}`;
      el('dw-stat-days').replaceChildren(document.createTextNode(String(report.activeDays)+' '));
      const denominator = document.createElement('em'); denominator.textContent = '/ '+report.days.length; el('dw-stat-days').append(denominator);
      el('dw-stat-schedule').textContent = `${report.scheduledDays} scheduled ${report.scheduledDays === 1 ? 'day' : 'days'}`;
      el('dw-activity-title').textContent = grouping === 'day' ? 'Daily focus' : 'Weekly focus';
      el('dw-offday-legend').hidden = grouping !== 'day';
      renderChart(report,grouping,today);
      el('dw-chart-note').textContent = `${grouping === 'week' ? 'Click a week to see its sessions.' : 'Click a day to see its sessions.'} All focus time is included, even on days off.`;
      renderRows(report);
      paintStorage();
    }
    function renderChart(report,grouping,today) {
      const chart = el('dw-chart');
      const focusedKey = chart.contains(document.activeElement) ? document.activeElement.dataset.key : null;
      chart.replaceChildren();
      const count = report.buckets.length;
      chart.style.gridTemplateColumns = `repeat(${Math.max(1,count)},minmax(35px,1fr))`;
      chart.style.minWidth = count > 14 ? `${count*44}px` : '100%';
      chart.setAttribute('aria-label',`Focus time by ${grouping}. Select a bar to open that ${grouping}.`);
      const max = Math.max(1,...report.buckets.map(b => b.focusMs));
      for (const bucket of report.buckets) {
        const offday = grouping === 'day' && !R.isScheduled(bucket.key,schedule);
        const button = document.createElement('button'); button.type = 'button'; button.className = 'dw-bar-column';
        button.dataset.key = bucket.key; button.dataset.offday = String(offday); button.dataset.empty = String(bucket.focusMs === 0); button.dataset.today = String(bucket.key === today);
        const label = grouping === 'week' ? dateLabel(R.dateAt(bucket.key)) : count <= 7 && period === 'week' ? dateLabel(R.dateAt(bucket.key),{weekday:'short'}) : dateLabel(R.dateAt(bucket.key));
        button.setAttribute('aria-label',`${dateLabel(R.dateAt(bucket.key),{weekday:'long',month:'long',day:'numeric',year:'numeric'})}${grouping === 'week' ? ', week' : ''}: ${duration(bucket.focusMs,true)}, ${bucket.cycles} completed cycles${offday ? ', day off' : ''}. View report.`);
        button.title = button.getAttribute('aria-label');
        const value = document.createElement('span'); value.className = 'dw-bar-value'; value.textContent = duration(bucket.focusMs);
        const bar = document.createElement('span'); bar.className = 'dw-bar'; bar.style.height = Math.max(3,bucket.focusMs/max*105)+'px';
        const caption = document.createElement('span'); caption.className = 'dw-bar-label'; caption.textContent = label;
        button.append(value,bar,caption); button.addEventListener('click',()=>{period = grouping; reportDate = bucket.key; pageNumber = 0; el('dw-grouping').value = 'day'; renderJournal();});
        chart.append(button);
        if (bucket.key === focusedKey) button.focus({preventScroll:true});
      }
    }
    function renderRows(report) {
      const rows = report.rows, empty = rows.length === 0;
      pageNumber = Math.max(0,Math.min(pageNumber,Math.ceil(rows.length/pageSize)-1));
      el('dw-session-count').textContent = rows.length;
      el('dw-empty').hidden = !empty; el('dw-session-table-wrap').hidden = empty;
      el('dw-export').disabled = empty;
      el('dw-session-pagination').hidden = rows.length <= pageSize;
      el('dw-page-prev').disabled = pageNumber === 0; el('dw-page-next').disabled = (pageNumber+1)*pageSize >= rows.length;
      el('dw-page-info').textContent = `${pageNumber*pageSize+1}–${Math.min((pageNumber+1)*pageSize,rows.length)} of ${rows.length}`;
      const body = el('dw-session-rows'); body.replaceChildren();
      for (const row of rows.slice(pageNumber*pageSize,(pageNumber+1)*pageSize)) {
        const tr = document.createElement('tr'); tr.dataset.recordId = row.id;
        const started = document.createElement('td'); started.textContent = dateLabel(row.start); const startTime = document.createElement('small'); startTime.textContent = timeLabel(row.start); started.append(startTime); started.title = new Date(row.start).toString();
        const ended = document.createElement('td'); ended.textContent = row.status === 'live' ? paused ? 'Paused' : 'In progress' : dateLabel(row.end);
        const endTime = document.createElement('small'); endTime.textContent = row.status === 'live' ? 'Current session' : timeLabel(row.end); ended.append(endTime); ended.title = new Date(row.end).toString();
        const time = document.createElement('td'); time.className = 'dw-align-right'; time.textContent = duration(row.focusMs,true);
        const planned = document.createElement('small'); planned.textContent = row.focusMs < row.totalFocusMs ? `${duration(row.totalFocusMs,true)} total` : `${duration(row.plannedMs)} planned`; time.append(planned);
        const state = document.createElement('td'); state.className = 'dw-align-right';
        const badge = document.createElement('span'); badge.className = 'dw-cycle-state'; badge.dataset.state = row.status;
        const dot = document.createElement('span'); dot.className = 'dw-state-dot'; dot.setAttribute('aria-hidden','true');
        badge.append(dot,document.createTextNode(row.status === 'complete' ? 'Complete' : row.status === 'live' ? paused ? 'Paused' : 'Live' : 'Partial')); state.append(badge);
        if (row.status === 'complete' && !row.completionInRange) { const outside = document.createElement('small'); outside.textContent = 'Outside range'; state.append(outside); }
        tr.append(started,ended,time,state); body.append(tr);
      }
      el('dw-accounting-note').textContent = 'Focus time is clipped to this range. Pauses and breaks are excluded. A completed cycle is counted at its finish time; partial sessions add time only.';
    }
    function openSchedule() {
      el('dw-schedule-mode').value = schedule.mode;
      for (const checkbox of el('dw-weekday-buttons').querySelectorAll('input')) checkbox.checked = schedule.weekdays.includes(Number(checkbox.value));
      el('dw-shift-on').value = schedule.on; el('dw-shift-off').value = schedule.off; el('dw-shift-anchor').value = schedule.anchor;
      el('dw-week-start').value = schedule.weekStart;
      el('dw-day-start').value = String(Math.floor(schedule.cutoff/60)).padStart(2,'0')+':'+String(schedule.cutoff%60).padStart(2,'0');
      el('dw-journal-report').hidden = true; el('dw-schedule-panel').hidden = false; previewSchedule(); el('dw-schedule-mode').focus();
    }
    function scheduleDraft() {
      const on = el('dw-shift-on').valueAsNumber, off = el('dw-shift-off').valueAsNumber, time = el('dw-day-start').value;
      const draft = {mode:el('dw-schedule-mode').value,weekdays:[...el('dw-weekday-buttons').querySelectorAll('input:checked')].map(i=>Number(i.value)),on,off,anchor:el('dw-shift-anchor').value,weekStart:Number(el('dw-week-start').value),cutoff:Number(time.slice(0,2))*60+Number(time.slice(3,5))};
      let error = '';
      if (!/^\d{2}:\d{2}$/.test(time)) error = 'Choose a valid reporting-day start time.';
      if (draft.mode === 'shifts') {
        if (![on,off].every(n => Number.isInteger(n) && n >= 1 && n <= 31)) error = 'Choose 1–31 work days and 1–31 rest days.';
        try { R.dateAt(draft.anchor); } catch (_) { error = 'Choose the first work day of your shift pattern.'; }
      }
      return {draft,error};
    }
    function previewSchedule() {
      const {draft,error} = scheduleDraft();
      el('dw-weekdays-setting').hidden = draft.mode !== 'weekdays'; el('dw-shifts-setting').hidden = draft.mode !== 'shifts'; el('dw-everyday-setting').hidden = draft.mode !== 'everyday';
      el('dw-schedule-error').hidden = !error; el('dw-schedule-error').textContent = error; el('dw-save-schedule').disabled = !!error;
      const container = el('dw-schedule-days'); container.replaceChildren(); if (error) return;
      const today = R.dayKey(Date.now(),draft.cutoff);
      for (let i = 0; i < 14; i++) {
        const key = R.addDays(today,i), at = R.dateAt(key), work = R.isScheduled(key,draft);
        const cell = document.createElement('div'); cell.className = 'dw-schedule-day'; cell.dataset.work = String(work); cell.title = dateLabel(at,{weekday:'long',month:'long',day:'numeric'})+' · '+(work?'Work':'Rest');
        const label = document.createElement('small'); label.textContent = dateLabel(at,{weekday:'short'}).slice(0,2);
        const number = document.createElement('strong'); number.textContent = new Date(at).getDate(); cell.append(label,number); container.append(cell);
      }
    }
    function closeSchedule() { el('dw-journal-report').hidden = false; el('dw-schedule-panel').hidden = true; renderJournal(); el('dw-open-schedule').focus(); }
    function downloadCSV(report,bounds,example,allSessions = false) {
      if (!report?.rows.length || !bounds.valid) return false;
      const stamp = at => { const d = new Date(at), offset = -d.getTimezoneOffset(), sign = offset >= 0 ? '+' : '-'; return `${R.localKey(at)}T${timeLabel(at)}:${String(d.getSeconds()).padStart(2,'0')}${sign}${String(Math.floor(Math.abs(offset)/60)).padStart(2,'0')}:${String(Math.abs(offset)%60).padStart(2,'0')}`; };
      const columns = ['Data','Report from','Report until (exclusive)','Reporting day starts','Schedule','Session ID','Started','Ended / observed at','Outcome','Planned minutes','Focus seconds in range','Total focus seconds','Completed cycle in range'];
      const rows = report.rows.map(r=>[example?'Example':'Journal',allSessions?'':stamp(bounds.from),allSessions?'':stamp(bounds.to),String(Math.floor(schedule.cutoff/60)).padStart(2,'0')+':'+String(schedule.cutoff%60).padStart(2,'0'),scheduleSummary(),r.id,stamp(r.start),stamp(r.end),r.status,r.plannedMs/MINUTE,Number((r.focusMs/1000).toFixed(3)),Number((r.totalFocusMs/1000).toFixed(3)),r.completionInRange?1:0]);
      const quote = value => '"'+String(value).replace(/"/g,'""')+'"';
      const blob = new Blob(['\uFEFF'+[columns,...rows].map(row=>row.map(quote).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'});
      const url = URL.createObjectURL(blob), link = document.createElement('a'); link.href = url; link.download = allSessions ? 'deep-work-journal-all-sessions.csv' : `deep-work-${example?'example-':''}${R.localKey(bounds.from)}-to-${R.localKey(bounds.to)}.csv`; document.body.append(link); link.click(); link.remove(); setTimeout(()=>URL.revokeObjectURL(url),1000); announce('Report exported as CSV.');
      return true;
    }
    function exportCSV() { renderJournal(); downloadCSV(currentReport,currentBounds,sampleMode); }
    function settingsExportData(now = Date.now()) {
      if (reconcile(now)) { paintPhase();persist(now); }
      if (el('dw-settings-export-scope').value === 'current') {
        const bounds = reportBounds();
        const report = R.buildReport(getRecords(now),bounds.valid?bounds.from:NaN,bounds.valid?bounds.to:NaN,schedule,'day');
        return {report,bounds,example:sampleMode,allSessions:false};
      }
      const rows = actualRecords(now).map(record=>{
        const totalFocusMs = record.segments.reduce((sum,segment)=>sum+Math.max(0,segment.end-segment.start),0);
        return {...record,focusMs:totalFocusMs,totalFocusMs,completionInRange:record.status === 'complete'};
      }).filter(record=>record.focusMs > 0 || record.completionInRange).sort((left,right)=>right.start-left.start);
      return {report:{rows},bounds:{valid:true},example:false,allSessions:true};
    }
    function paintSettings(now = Date.now()) {
      lastSettingsPaint = now;
      const data = settingsExportData(now), count = data.report.rows.length;
      const total = data.report.rows.reduce((sum,row)=>sum+row.focusMs,0);
      el('dw-settings-export-button').disabled = !data.bounds.valid || count === 0;
      el('dw-settings-export-note').textContent = !data.bounds.valid ? 'Choose a valid date range in Journal first.' : data.allSessions ? count ? `${count} ${count === 1 ? 'session' : 'sessions'} · ${duration(total,true)} of focus. Includes all of your journal history.` : 'Your journal has no sessions yet. Choose Current Journal Report to export the example.' : `${data.example ? 'Example data' : 'Your journal'} · ${count} ${count === 1 ? 'session' : 'sessions'} · ${duration(total,true)} of focus in the selected Journal range.`;
      el('dw-settings-storage-status').textContent = settingsStorageAvailable ? 'Settings saved on this device' : 'Settings could not be saved. They last only while this preview is open.';
    }
    function saveAppSettings() {
      if (!settingsStorageAvailable) { paintSettings(); return false; }
      try { localStorage.setItem(SETTINGS_KEY,JSON.stringify({version:1,...appSettings}));paintSettings();return true; }
      catch (_) { settingsStorageAvailable = false;paintSettings();return false; }
    }
    function validateFeedback() {
      const email = el('dw-feedback-email'), message = el('dw-feedback-message');
      const emailValid = email.validity.valid;
      const messageValid = message.value.trim().length >= 5 && message.value.length <= 5000;
      email.setAttribute('aria-invalid',String(!emailValid)); message.setAttribute('aria-invalid',String(!messageValid));
      const error = !emailValid ? 'Enter a valid email address, or leave it blank.' : !messageValid ? 'Write a message between 5 and 5,000 characters.' : '';
      el('dw-feedback-error').hidden = !error;el('dw-feedback-error').textContent = error;
      if (error) {el('dw-feedback-status').textContent = '';(!emailValid?email:message).focus();return null;}
      return {type:el('dw-feedback-type').value,email:email.value.trim(),message:message.value.trim()};
    }
    async function copyFeedback() {
      const draft = validateFeedback(); if (!draft) return;
      const names = {idea:'Suggestion',problem:'Problem report',general:'General feedback'};
      const text = `Deep Work feedback\nType: ${names[draft.type]}${draft.email?'\nEmail: '+draft.email:''}\n\n${draft.message}`;
      let copied = false;
      try { if (navigator.clipboard?.writeText) {await navigator.clipboard.writeText(text);copied = true;} } catch (_) {}
      if (!copied) {
        const temporary = document.createElement('textarea');temporary.value = text;temporary.readOnly = true;temporary.style.cssText = 'position:fixed;left:-9999px;top:0;opacity:0;';document.body.append(temporary);temporary.select();
        try {copied = document.execCommand('copy');} catch (_) {} finally {temporary.remove();}
      }
      el('dw-feedback-status').textContent = copied ? 'Feedback copied. Nothing has been sent.' : 'Copy is unavailable here. Select and copy your message below.';
      if (copied) el('dw-feedback-copy').focus(); else {el('dw-feedback-message').focus();el('dw-feedback-message').select();}
    }
    function initializeSettings() {
      el('dw-launch-login').checked = appSettings.launchAtLogin;
      el('dw-feedback-type').value = appSettings.feedbackDraft.type;
      el('dw-feedback-email').value = appSettings.feedbackDraft.email;
      el('dw-feedback-message').value = appSettings.feedbackDraft.message;
      el('dw-feedback-form').noValidate = true;
      el('dw-launch-login').addEventListener('change',()=>{appSettings.launchAtLogin = el('dw-launch-login').checked;saveAppSettings();announce(appSettings.launchAtLogin?'Launch at Login preference enabled for the Mac app preview.':'Launch at Login preference disabled.');});
      el('dw-settings-export-scope').addEventListener('change',()=>{el('dw-settings-export-status').textContent = '';paintSettings();});
      el('dw-settings-export-button').addEventListener('click',()=>{const data=settingsExportData();if(downloadCSV(data.report,data.bounds,data.example,data.allSessions))el('dw-settings-export-status').textContent = data.example?'Example report exported as CSV.':'Your journal exported as CSV.';else paintSettings();});
      el('dw-feedback-form').addEventListener('submit',event=>{event.preventDefault();const draft=validateFeedback();if(!draft)return;appSettings.feedbackDraft=draft;const didSave=saveAppSettings();el('dw-feedback-status').textContent = didSave?'Draft saved on this device. Nothing has been sent.':'Draft could not be saved. Use Copy Feedback to keep it.';});
      el('dw-feedback-copy').addEventListener('click',copyFeedback);
      for(const input of el('dw-feedback-form').querySelectorAll('input,textarea,select'))input.addEventListener('input',()=>{el('dw-feedback-error').hidden=true;el('dw-feedback-status').textContent='';input.removeAttribute('aria-invalid');});
      if(appSettings.feedbackDraft.message)el('dw-feedback-status').textContent='Your saved draft is ready.';
    }

    el('dw-start').addEventListener('click',()=>{const focus = readMinutes(focusSelect,focusInput), rest = readMinutes(breakSelect,breakInput); if (focus === null || rest === null) {updateSetup();return;} focusMinutes = focus; breakMinutes = rest; beginPhase('focus');});
    for (const [select,input] of [[focusSelect,focusInput],[breakSelect,breakInput]]) {
      select.addEventListener('change',()=>{updateSetup();persist();if(select.value === 'custom'){input.focus();input.select();}});
      input.addEventListener('input',()=>{updateSetup();persist();});
    }
    el('dw-pause').addEventListener('click',()=>{
      const now = Date.now();
      if (done) {beginPhase('focus',now);return;}
      reconcile(now);
      if (done) {paintPhase();persist(now);return;}
      if (paused) {paused = false;restored = false;deadline = now+remainingMs;if(currentCycle)currentCycle.openStart = now;startTicker();}
      else {remainingMs = Math.max(0,deadline-now);sealSegment(now);paused = true;clearTicker();}
      paintPhase();persist(now);announce(paused?'Timer paused. Focus time saved.':'Timer resumed.');
    });
    el('dw-next').addEventListener('click',()=>{
      const now = Date.now(), requestedPhase = phase; reconcile(now);
      if (done || phase !== requestedPhase) {paintPhase();persist(now);return;}
      if (phase === 'focus') {finalizeFocus(now,'partial');beginPhase('break',now);}
      else if (repeating) beginPhase('focus',now);
      else {finishPair();paintPhase();persist(now);}
    });
    repeatInput.addEventListener('change',()=>{const now = Date.now();reconcile(now);repeating = repeatInput.checked;phase === 'setup'?updateSetup():paintPhase();persist(now);announce(repeating?'Repeat enabled.':'Repeat disabled. The current focus and break pair will finish, then stop.');});
    el('dw-end').addEventListener('click',()=>{
      const now = Date.now();reconcile(now);if(currentCycle)finalizeFocus(now,'partial');clearTicker();phase = 'setup';paused = false;done = false;restored = false;totalMs = 0;remainingMs = 0;updateSetup();paintPhase();persist(now);announce('Session ended and saved to your journal.');el('dw-start').focus();
    });
    el('dw-close').addEventListener('click',()=>{tick();persist();appWindow.hidden = true;el('dw-menu-status').setAttribute('aria-expanded','false');el('dw-menu-status').focus();announce('Window hidden. Open Deep Work from the menu bar.');});
    el('dw-menu-status').addEventListener('click',()=>{tick();appWindow.hidden = false;el('dw-menu-status').setAttribute('aria-expanded','true');setView('focus');phase === 'setup'?focusSelect.focus():el('dw-pause').focus();announce('Deep Work window reopened.');});
    for (const key of views) {
      el('dw-tab-'+key).addEventListener('click',()=>setView(key));
      el('dw-tab-'+key).addEventListener('keydown',event=>{if(['ArrowLeft','ArrowRight','Home','End'].includes(event.key)){event.preventDefault();const next = event.key==='Home'?0:event.key==='End'?views.length-1:(views.indexOf(key)+(event.key==='ArrowRight'?1:-1)+views.length)%views.length;setView(views[next],true);}});
    }
    for (const button of root.querySelectorAll('[data-period]')) button.addEventListener('click',()=>{period = button.dataset.period;pageNumber = 0;renderJournal();});
    el('dw-report-date').addEventListener('change',()=>{if(el('dw-report-date').value){reportDate = el('dw-report-date').value;pageNumber = 0;renderJournal();}});
    for (const [id,direction] of [['dw-previous-period',-1],['dw-next-period',1]]) el(id).addEventListener('click',()=>{reportDate = R.addDays(reportDate,direction*(period==='week'?7:1));pageNumber = 0;renderJournal();});
    el('dw-today').addEventListener('click',()=>{reportDate = R.dayKey(Date.now(),schedule.cutoff);if(period==='range')period='day';pageNumber = 0;renderJournal();});
    for (const id of ['dw-range-from','dw-range-to']) el(id).addEventListener('change',()=>{pageNumber=0;renderJournal();});
    el('dw-grouping').addEventListener('change',()=>renderJournal());
    const toggleSample = () => {sampleMode = !sampleMode;pageNumber = 0;renderJournal();};
    el('dw-toggle-sample').addEventListener('click',toggleSample);el('dw-show-own').addEventListener('click',toggleSample);
    el('dw-empty-focus').addEventListener('click',()=>{sampleMode=false;setView('focus');focusSelect.focus();});
    el('dw-page-prev').addEventListener('click',()=>{pageNumber--;renderJournal();});el('dw-page-next').addEventListener('click',()=>{pageNumber++;renderJournal();});
    el('dw-open-schedule').addEventListener('click',openSchedule);el('dw-cancel-schedule').addEventListener('click',closeSchedule);
    for (const input of el('dw-schedule-panel').querySelectorAll('input,select')) input.addEventListener('input',previewSchedule);
    el('dw-save-schedule').addEventListener('click',()=>{const {draft,error} = scheduleDraft();if(error)return;schedule=draft;pageNumber=0;const now=Date.now();reconcile(now);persist(now);closeSchedule();announce('Work schedule saved. Reports updated.');});
    el('dw-export').addEventListener('click',exportCSV);
    document.addEventListener('visibilitychange',()=>{tick();persist();});
    window.addEventListener('pagehide',()=>{const now=Date.now();reconcile(now);persist(now);});
    window.addEventListener('storage',event=>{if(event.key!==STORAGE_KEY)return;try{const changed=JSON.parse(event.newValue||'null');if(Array.isArray(changed?.records)){mergeRecords(changed.records);if(readOnly)passiveCycle=changed?.active?.phase==='focus'?cleanRecord(changed.active.currentCycle):null;if(view==='journal')renderJournal();}}catch(_){}});
    sampleRecords = makeSampleData();
    initializeSettings();
    el('dw-report-date').value = reportDate;
    const week = R.weekKey(reportDate,schedule.weekStart);
    el('dw-range-from').value = localDateTime(R.dateAt(week,schedule.cutoff));el('dw-range-to').value = localDateTime(R.dateAt(R.addDays(week,7),schedule.cutoff));
    updateSetup();paintPhase();setView('journal');paintStorage();
    // Reopened previews resume only on request; time while the file was closed is never invented.
    if (restored) announce('Your unfinished session was restored paused at its last saved point.');
  }
  function boot() {
    // One timer owner per browser; another open copy can browse without changing its checkpoint.
    if (navigator.locks?.request) {
      navigator.locks.request('deep-work-preview-timer',{ifAvailable:true},lock=>{
        initializeDeepWork(!lock);
        if (lock) return new Promise(resolve=>window.addEventListener('pagehide',resolve,{once:true}));
      }).catch(()=>initializeDeepWork());
    } else initializeDeepWork();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
})();
