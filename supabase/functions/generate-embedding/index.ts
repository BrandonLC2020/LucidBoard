import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

serve(async (req) => {
  try {
    const payload = await req.json()
    const { type, record, old_record } = payload

    if (type !== 'INSERT' && type !== 'UPDATE') {
      return new Response('OK', { status: 200 })
    }

    const note = record

    if (!note.content_text || note.content_text.trim() === '') {
      return new Response('No content to embed', { status: 200 })
    }

    // Skip UPDATE when content_text is unchanged to avoid redundant API calls
    if (type === 'UPDATE' && old_record?.content_text === note.content_text) {
      return new Response('Content unchanged', { status: 200 })
    }

    const embeddingRes = await fetch('https://api.openai.com/v1/embeddings', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'text-embedding-3-small',
        input: note.content_text.trim(),
      }),
    })

    if (!embeddingRes.ok) {
      const error = await embeddingRes.text()
      console.error('OpenAI error:', error)
      return new Response('Embedding generation failed', { status: 500 })
    }

    const { data } = await embeddingRes.json()
    const embedding: number[] = data[0].embedding

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

    const { error } = await supabase
      .from('notes')
      .update({ embedding })
      .eq('id', note.id)

    if (error) {
      console.error('Supabase update error:', error)
      return new Response('Failed to store embedding', { status: 500 })
    }

    return new Response('OK', { status: 200 })
  } catch (err) {
    console.error('Unexpected error:', err)
    return new Response('Internal error', { status: 500 })
  }
})
