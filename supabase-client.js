/**
 * Supabase Client para PC na Veia
 * Substitui localStorage por Supabase com fallback offline
 */
(function () {
  "use strict";

  // ===== CONFIG =====
  // A chave publishable é pública por design: fica visível em qualquer
  // navegador. Quem protege os dados é o RLS do supabase-schema.sql.
  // NUNCA coloque aqui a secret key (sb_secret_...) — ela contorna o RLS.
  const SUPABASE_URL = "https://cwqzirfsrdrmjwlpyalb.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_6nkEK51sXLRhq8X6FLlTDA_E7xkUZ5v";

  // ===== ESTADO =====
  let supabase = null;
  let currentUser = null;
  let authReady = false;
  let pendingWrites = new Map(); // queue para modo offline
  let isOnline = navigator.onLine;

  // ===== INIT =====
  async function initSupabase() {
    if (typeof window.supabase === "undefined") {
      console.warn("[Supabase] SDK não carregado. Usando localStorage fallback.");
      return false;
    }

    supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
      db: { schema: "public" },
    });

    // Listener de auth
    supabase.auth.onAuthStateChange((event, session) => {
      currentUser = session?.user ?? null;
      authReady = true;
      window.dispatchEvent(new CustomEvent("pcnaveia:auth", { detail: { user: currentUser, event } }));
      if (currentUser) {
        syncPendingWrites();
        loadAllFromCloud();
      }
      // Só limpa o cache no logout explícito. Nos demais eventos
      // (INITIAL_SESSION, TOKEN_REFRESHED, recovery de senha) fica sem
      // sessão por um instante — limpar ali apagaria progresso em cache.
      if (event === "SIGNED_OUT") {
        clearLocalCache();
      }
    });

    // Verifica sessão existente
    const { data: { session } } = await supabase.auth.getSession();
    currentUser = session?.user ?? null;
    authReady = true;

    // Online/offline
    window.addEventListener("online", () => { isOnline = true; syncPendingWrites(); });
    window.addEventListener("offline", () => { isOnline = false; });

    return true;
  }

  // ===== HELPERS =====
  function uid() { return currentUser?.id; }
  function assertAuth() { if (!uid()) throw new Error("Usuário não autenticado"); }

  function queueWrite(table, data, op = "upsert", onConflict) {
    const key = `${op}:${table}:${JSON.stringify(data)}`;
    pendingWrites.set(key, { table, data, op, onConflict, ts: Date.now() });
    persistQueue();
  }

  function persistQueue() {
    try {
      localStorage.setItem("pcnaveia:write_queue", JSON.stringify([...pendingWrites.values()]));
    } catch (e) { /* ignore */ }
  }

  function loadQueue() {
    try {
      const raw = localStorage.getItem("pcnaveia:write_queue");
      if (raw) {
        JSON.parse(raw).forEach(w => {
          const op = w.op || "upsert";
          pendingWrites.set(`${op}:${w.table}:${JSON.stringify(w.data)}`, { ...w, op });
        });
      }
    } catch (e) { /* ignore */ }
  }

  async function syncPendingWrites() {
    if (!isOnline || !currentUser) return;
    const queue = [...pendingWrites.entries()];
    for (const [key, w] of queue) {
      try {
        let res;
        if (w.op === "insert") {
          // certificates é append-only: não tem unique para ON CONFLICT
          res = await supabase.from(w.table).insert(w.data);
        } else {
          res = await supabase.from(w.table).upsert(w.data, w.onConflict ? { onConflict: w.onConflict } : undefined);
        }
        // upsert/insert resolvem com { error: null } em vez de lançar
        if (res && res.error) throw res.error;
        pendingWrites.delete(key);
      } catch (e) {
        console.warn("[Supabase] Falha ao sincronizar:", (e && e.message) || e);
        break; // para na primeira falha, tenta depois
      }
    }
    persistQueue();
  }

  function clearLocalCache() {
    // limpa chaves locais antigas (migração)
    const keys = Object.keys(localStorage).filter(k => k.startsWith("pcnaveia:"));
    keys.forEach(k => localStorage.removeItem(k));
  }

  // ===== CRUD GENÉRICO =====
  // Não injeta updated_at: as tabelas que têm essa coluna usam trigger
  // (set_updated_at). quiz_answers usa answered_at e certificates usa
  // issued_at — injetar updated_at aqui causaria "column does not exist".
  //
  // Não lança: se a escrita online falhar, enfileira para reenviar.
  // Perder o dado silenciosamente seria pior que sincronizar atrasado.
  async function upsert(table, row, matchKey) {
    assertAuth();
    const payload = { ...row, user_id: uid() };
    if (isOnline) {
      const { error } = await supabase.from(table).upsert(payload, { onConflict: matchKey });
      if (error) {
        console.warn("[Supabase] Escrita adiada para a fila:", error.message);
        queueWrite(table, payload, "upsert", matchKey);
        return false;
      }
      return true;
    }
    queueWrite(table, payload, "upsert", matchKey);
    return false;
  }

  async function select(table, filter = {}) {
    assertAuth();
    let query = supabase.from(table).select("*").eq("user_id", uid());
    Object.entries(filter).forEach(([k, v]) => query = query.eq(k, v));
    if (isOnline) {
      const { data, error } = await query;
      if (error) throw error;
      return data ?? [];
    }
    // Offline: lê do localStorage cache
    return readLocalCache(table, filter);
  }

  async function selectOne(table, filter) {
    const rows = await select(table, filter);
    return rows[0] ?? null;
  }

  // Cache local para leitura offline
  function cacheKey(table, filter) {
    return `pcnaveia:cache:${table}:${JSON.stringify(filter)}`;
  }

  function writeLocalCache(table, filter, data) {
    try { localStorage.setItem(cacheKey(table, filter), JSON.stringify(data)); } catch (e) {}
  }

  function readLocalCache(table, filter) {
    try {
      const raw = localStorage.getItem(cacheKey(table, filter));
      return raw ? JSON.parse(raw) : [];
    } catch (e) { return []; }
  }

  // ===== API ESPECÍFICA DO APP =====

  // Painéis (quiz + prática)
  async function savePanelProgress(panelKey, { quizCorrect, quizTotal, practiceDone, practiceTotal }) {
    await upsert("panel_progress", { panel_key: panelKey, quiz_correct: quizCorrect, quiz_total: quizTotal, practice_done: practiceDone, practice_total: practiceTotal }, "user_id,panel_key");
    writeLocalCache("panel_progress", { panel_key: panelKey }, [{ panel_key: panelKey, quiz_correct: quizCorrect, quiz_total: quizTotal, practice_done: practiceDone, practice_total: practiceTotal }]);
  }

  async function loadPanelProgress(panelKey) {
    return selectOne("panel_progress", { panel_key: panelKey });
  }

  async function loadAllPanelProgress() {
    return select("panel_progress");
  }

  // Quiz answers
  async function saveQuizAnswer(panelKey, questionId, chosenOpt, isCorrect) {
    await upsert("quiz_answers", { panel_key: panelKey, question_id: questionId, chosen_opt: chosenOpt, is_correct: isCorrect }, "user_id,panel_key,question_id");
  }

  async function loadQuizAnswers(panelKey) {
    return select("quiz_answers", { panel_key: panelKey });
  }

  async function loadAllQuizAnswers() {
    return select("quiz_answers");
  }

  // Checklists
  async function saveChecklistItem(checklistKey, itemKey, checked) {
    await upsert("checklist_items", { checklist_key: checklistKey, item_key: itemKey, checked }, "user_id,checklist_key,item_key");
  }

  async function loadChecklistItems(checklistKey) {
    return select("checklist_items", { checklist_key: checklistKey });
  }

  async function loadAllChecklistItems() {
    return select("checklist_items");
  }

  // Notes
  async function saveNote(noteKey, content) {
    await upsert("user_notes", { note_key: noteKey, content }, "user_id,note_key");
  }

  async function loadNote(noteKey) {
    return selectOne("user_notes", { note_key: noteKey });
  }

  async function loadAllNotes() {
    return select("user_notes");
  }

  // UI State
  async function saveUIState(key, value) {
    await upsert("ui_state", { key, value }, "user_id,key");
  }

  async function loadUIState(key) {
    const row = await selectOne("ui_state", { key });
    return row?.value ?? null;
  }

  // Certificados
  async function saveCertificate(type, title, payload) {
    // certificates usa issued_at, não updated_at
    const row = { certificate_type: type, title, payload, issued_at: new Date().toISOString() };
    assertAuth();
    row.user_id = uid();
    if (isOnline) {
      const { error } = await supabase.from("certificates").insert(row);
      if (error) {
        console.warn("[Supabase] Certificado adiado para a fila:", error.message);
        queueWrite("certificates", row, "insert");
        return false;
      }
      return true;
    }
    queueWrite("certificates", row, "insert");
    return false;
  }

  async function loadCertificates() {
    return select("certificates");
  }

  // Bulk load (otimiza primeira carga)
  async function loadAllFromCloud() {
    if (!isOnline || !currentUser) return;
    try {
      const [panels, quizzes, checks, notes, ui] = await Promise.all([
        loadAllPanelProgress(),
        loadAllQuizAnswers(),
        loadAllChecklistItems(),
        loadAllNotes(),
        select("ui_state"),
      ]);
      writeLocalCache("panel_progress", {}, panels);
      writeLocalCache("quiz_answers", {}, quizzes);
      writeLocalCache("checklist_items", {}, checks);
      writeLocalCache("user_notes", {}, notes);
      writeLocalCache("ui_state", {}, ui);
      window.dispatchEvent(new CustomEvent("pcnaveia:synced", { detail: { panels, quizzes, checks, notes, ui } }));
    } catch (e) {
      console.warn("[Supabase] Falha no bulk load:", e.message);
    }
  }

  // ===== AUTH UI =====
  async function signUp(email, password, metadata = {}) {
    const { data, error } = await supabase.auth.signUp({ email, password, options: { data: metadata } });
    if (error) throw error;
    return data;
  }

  // Reenvia a confirmação. O SDK v2 não expõe isso, então usa o endpoint
  // /resend que é o mesmo chamado por signUp() por baixo dos panos.
  // Nunca revela se o e-mail existe: a resposta é a mesma nos dois casos.
  async function resendConfirmation(email) {
    // Não exige sessão: quem acabou de cadastrar ainda não tem.
    const res = await fetch(`${SUPABASE_URL}/auth/v1/resend`, {
      method: "POST",
      headers: {
        apikey: SUPABASE_PUBLISHABLE_KEY,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ type: "signup", email }),
    });
    // 200 = reenviado. 429 = rate limit. 4xx = e-mail já confirmado/inexistente.
    // Só tratamos o rate limit como erro; o resto é resposta neutra de propósito.
    if (res.status === 429) {
      throw new Error("Muitas tentativas. Aguarde alguns instantes antes de reenviar.");
    }
    return true;
  }

  async function signIn(email, password) {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
    return data;
  }

  // GitHub Pages publica em https://<user>.github.io/<REPO>/ — usar apenas
  // a origin perderia o subdiretório e o callback cairia em 404.
  // Mantém o caminho e a query string (o code de confirmação vem neles).
  function redirectUrl() {
    return window.location.origin + window.location.pathname + window.location.search;
  }

  async function signInWithOAuth(provider) { // 'github' | 'google'
    const { data, error } = await supabase.auth.signInWithOAuth({ provider, options: { redirectTo: redirectUrl() } });
    if (error) throw error;
    return data;
  }

  async function signOut() {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    currentUser = null;
  }

  async function resetPassword(email) {
    const { error } = await supabase.auth.resetPasswordForEmail(email, { redirectTo: redirectUrl() });
    if (error) throw error;
  }

  async function updatePassword(newPassword) {
    const { error } = await supabase.auth.updateUser({ password: newPassword });
    if (error) throw error;
  }

  async function updateProfile(metadata) {
    const { data, error } = await supabase.auth.updateUser({ data: metadata });
    if (error) throw error;
    const row = {
      id: uid(),
      email: data.user.email,
      full_name: metadata.full_name || null,
      avatar_url: metadata.avatar_url || null,
      updated_at: new Date().toISOString(),
    };
    // profiles não tem user_id: usa a chave id, não o upsert genérico
    const { error: profileError } = await supabase.from("profiles").upsert(row, { onConflict: "id" });
    if (profileError) throw profileError;
    return data;
  }

  // ===== PROVIDERS =====
  // O endpoint /auth/v1/settings é público (não precisa de sessão e só
  // informa o que está habilitado). Cacheia para não repetir o fetch.
  const _providers = { chave: null, dados: null };
  async function providersHabilitados() {
    if (_providers.dados) return _providers.dados;
    try {
      const res = await fetch(`${SUPABASE_URL}/auth/v1/settings`, {
        headers: { apikey: SUPABASE_PUBLISHABLE_KEY },
      });
      if (!res.ok) throw new Error(res.status);
      _providers.dados = (await res.json()).external || {};
      return _providers.dados;
    } catch (e) {
      console.warn("[Supabase] Não deu para ler providers:", e.message);
      return null; // garoto-propaganda inofensivo: UI cai nos botões atuais
    }
  }
  // Verificação com cache curto expirado em 10s (mais simples que forçar refetch)
  let _provCacheT = 0;
  async function providerAtivo(provider) {
    const agora = Date.now();
    if (!_providers.dados || agora - _provCacheT > 10000) {
      _provCacheT = agora;
      _providers.dados = await providersHabilitados();
    }
    return !!( _providers.dados && _providers.dados[provider]);
  }

  // ===== INSTRUTOR =====
  // Painel do instrutor: só funciona se esta conta tiver role='instructor'
  // (as políticas RLS de supabase-instructor.sql negam para alunos).
  async function getMyProfile() {
    assertAuth();
    const { data, error } = await supabase
      .from("profiles")
      .select("id, email, full_name, role")
      .eq("id", uid())
      .maybeSingle();
    if (error) throw error;
    return data;
  }

  // Busca tudo o que o painel precisa. RLS garante que um aluno receba
  // vazio (ou erro 403) — nunca os dados dos colegas.
  async function getInstructorOverview() {
    assertAuth();
    const [profiles, progress, quizzes, checks, notes] = await Promise.all([
      supabase.from("profiles").select("id, email, full_name, role, created_at"),
      supabase.from("panel_progress").select("*"),
      supabase.from("quiz_answers").select("*"),
      supabase.from("checklist_items").select("*"),
      supabase.from("user_notes").select("*"),
    ]);
    for (const r of [profiles, progress, quizzes, checks, notes]) {
      if (r.error) throw r.error;
    }
    return {
      alunos: profiles.data,
      progresso: progress.data,
      quizzes: quizzes.data,
      checklists: checks.data,
      notas: notes.data,
    };
  }

  // ===== EXPORTA =====
  window.PCNaveiaSupabase = {
    init: initSupabase,
    // Auth
    signUp, signIn, signInWithOAuth, signOut, resetPassword, resendConfirmation,
    updatePassword, updateProfile,
    providerAtivo,
    getUser: () => currentUser,
    isAuthenticated: () => !!currentUser,
    onAuthChange: (fn) => window.addEventListener("pcnaveia:auth", e => fn(e.detail)),
    // Data
    savePanelProgress, loadPanelProgress, loadAllPanelProgress,
    saveQuizAnswer, loadQuizAnswers, loadAllQuizAnswers,
    saveChecklistItem, loadChecklistItems, loadAllChecklistItems,
    saveNote, loadNote, loadAllNotes,
    saveUIState, loadUIState,
    saveCertificate, loadCertificates,
    syncPendingWrites, loadAllFromCloud,
    // Instrutor
    getMyProfile, getInstructorOverview,
    // Utils
    isOnline: () => isOnline,
  };

  // Carrega fila pendente
  loadQueue();

  // Auto-init se SDK já estiver na página
  if (document.readyState !== "loading") {
    initSupabase();
  } else {
    document.addEventListener("DOMContentLoaded", initSupabase);
  }
})();