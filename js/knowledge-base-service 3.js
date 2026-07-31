(function initKnowledgeBaseService(window) {
  const config = window.AGENT_BUILDER_SUPABASE_CONFIG || {};
  const supabaseFactory = window.supabase;
  const client = config.url && config.publishableKey && supabaseFactory?.createClient
    ? supabaseFactory.createClient(config.url, config.publishableKey, {
      auth: {
        autoRefreshToken: true,
        persistSession: true
      }
    })
    : null;

  const DEFAULT_ACCOUNT_ID = config.defaultAccountId || '00000000-0000-0000-0000-000000000001';
  const STORAGE_BUCKET = config.storageBucket || 'knowledge-raw';

  function isConfigured() {
    return Boolean(client);
  }

  async function getUser() {
    if (!client) return null;
    const { data, error } = await client.auth.getUser();
    if (error) return null;
    return data?.user || null;
  }

  async function requireUser() {
    const user = await getUser();
    if (!user) {
      throw new Error('Supabase session not found. Sign in before persisting knowledge bases.');
    }

    return user;
  }

  function normalizeVisibility(value) {
    if (value === 'public' || value === 'publico') return 'public';
    return 'private';
  }

  function mapKnowledgeBase(row) {
    return {
      id: row.id,
      name: row.name,
      description: row.description || '',
      visibility: row.visibility,
      status: row.status,
      createdAt: row.created_at,
      updatedAt: row.updated_at
    };
  }

  function mapSource(row) {
    return {
      id: row.id,
      knowledgeBaseId: row.knowledge_base_id,
      name: row.title,
      type: row.type,
      sizeBytes: row.size_bytes,
      size: formatSourceSize(row.size_bytes),
      status: row.status,
      updatedAt: row.updated_at,
      sourceUrl: row.source_url,
      storageBucket: row.storage_bucket,
      storagePath: row.storage_path,
      mimeType: row.mime_type,
      metadata: row.metadata || {}
    };
  }

  function formatSourceSize(sizeBytes) {
    if (!sizeBytes) return '-';
    const sizeInMb = sizeBytes / (1024 * 1024);
    return `${sizeInMb.toFixed(1)} MB`;
  }

  function getSourceLabel(type) {
    const labels = {
      file: 'Arquivo',
      qa: 'Pergunta',
      site: 'Site/Blog',
      page: 'Página',
      pages: 'Página',
      youtube: 'YouTube',
      audio: 'Áudio'
    };

    return labels[type] || 'Arquivo';
  }

  async function listKnowledgeBases() {
    if (!client) return [];

    const { data, error } = await client
      .from('knowledge_bases')
      .select('*')
      .neq('status', 'deleted')
      .order('updated_at', { ascending: false });

    if (error) throw error;
    return (data || []).map(mapKnowledgeBase);
  }

  async function createKnowledgeBase(input) {
    const user = await requireUser();

    const { data, error } = await client
      .from('knowledge_bases')
      .insert({
        account_id: DEFAULT_ACCOUNT_ID,
        created_by: user.id,
        name: input.name,
        description: input.description || null,
        visibility: normalizeVisibility(input.visibility)
      })
      .select()
      .single();

    if (error) throw error;
    return mapKnowledgeBase(data);
  }

  async function updateKnowledgeBase(id, input) {
    await requireUser();

    const { data, error } = await client
      .from('knowledge_bases')
      .update({
        name: input.name,
        description: input.description || null,
        visibility: normalizeVisibility(input.visibility)
      })
      .eq('id', id)
      .select()
      .single();

    if (error) throw error;
    return mapKnowledgeBase(data);
  }

  async function deleteKnowledgeBase(id) {
    await requireUser();

    const { data, error } = await client
      .from('knowledge_bases')
      .delete()
      .eq('id', id)
      .select('id')
      .maybeSingle();

    if (error) throw error;
    if (!data) throw new Error('Knowledge base was not deleted. Check permissions or session state.');
  }

  async function listSources(knowledgeBaseId) {
    if (!client || !knowledgeBaseId) return [];

    const { data, error } = await client
      .from('knowledge_base_sources')
      .select('*')
      .eq('knowledge_base_id', knowledgeBaseId)
      .order('updated_at', { ascending: false });

    if (error) throw error;
    return (data || []).map(mapSource);
  }

  async function createSource(knowledgeBaseId, input) {
    const user = await requireUser();
    const normalizedType = input.type === 'pages' ? 'page' : input.type;

    const { data, error } = await client
      .from('knowledge_base_sources')
      .insert({
        knowledge_base_id: knowledgeBaseId,
        account_id: DEFAULT_ACCOUNT_ID,
        created_by: user.id,
        type: normalizedType,
        title: input.title,
        source_url: input.sourceUrl || null,
        storage_bucket: input.storagePath ? STORAGE_BUCKET : null,
        storage_path: input.storagePath || null,
        mime_type: input.mimeType || null,
        size_bytes: input.sizeBytes || null,
        status: input.status || 'queued',
        metadata: input.metadata || {}
      })
      .select()
      .single();

    if (error) throw error;
    return mapSource(data);
  }

  async function updateSource(id, input) {
    await requireUser();
    const normalizedType = input.type === 'pages' ? 'page' : input.type;

    const { data, error } = await client
      .from('knowledge_base_sources')
      .update({
        type: normalizedType,
        title: input.title,
        source_url: input.sourceUrl || null,
        status: input.status || 'queued',
        metadata: input.metadata || {}
      })
      .eq('id', id)
      .select()
      .single();

    if (error) throw error;
    return mapSource(data);
  }

  async function deleteSource(id) {
    await requireUser();

    const { data: source, error: sourceError } = await client
      .from('knowledge_base_sources')
      .select('id, storage_bucket, storage_path')
      .eq('id', id)
      .maybeSingle();

    if (sourceError) throw sourceError;
    if (!source) throw new Error('Knowledge source was not found. Check permissions or session state.');

    if (source.storage_path) {
      const { error: storageError } = await client.storage
        .from(source.storage_bucket || STORAGE_BUCKET)
        .remove([source.storage_path]);

      if (storageError) throw storageError;
    }

    const { data, error } = await client
      .from('knowledge_base_sources')
      .delete()
      .eq('id', id)
      .select('id')
      .maybeSingle();

    if (error) throw error;
    if (!data) throw new Error('Knowledge source was not deleted. Check permissions or session state.');
  }

  async function uploadFile(knowledgeBaseId, sourceId, file) {
    await requireUser();

    const safeName = file.name.replace(/[^\w.\-]+/g, '-');
    const storagePath = `accounts/${DEFAULT_ACCOUNT_ID}/knowledge-bases/${knowledgeBaseId}/sources/${sourceId}/${Date.now()}-${safeName}`;
    const { data, error } = await client.storage
      .from(STORAGE_BUCKET)
      .upload(storagePath, file, { upsert: false });

    if (error) throw error;
    return data.path;
  }

  window.KnowledgeBaseService = {
    client,
    isConfigured,
    getUser,
    listKnowledgeBases,
    createKnowledgeBase,
    updateKnowledgeBase,
    deleteKnowledgeBase,
    listSources,
    createSource,
    updateSource,
    deleteSource,
    uploadFile,
    getSourceLabel,
    formatSourceSize
  };
})(window);
