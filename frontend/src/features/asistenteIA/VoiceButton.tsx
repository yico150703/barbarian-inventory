import { useEffect, useRef, useState } from 'react'
import { Mic, Square } from 'lucide-react'
import { solicitar } from './service'

export function VoiceButton({ token, disabled, onText, onError, onBusy }: {
  token: string; disabled: boolean; onText: (text: string) => void
  onError: (error: string) => void; onBusy: (busy: boolean) => void
}) {
  const [recording, setRecording] = useState(false)
  const [sending, setSending] = useState(false)
  const [message, setMessage] = useState('')
  const [failed, setFailed] = useState(false)
  const [audioUrl, setAudioUrl] = useState('')
  const preview = useRef('')
  const recorder = useRef<MediaRecorder | null>(null)
  const stream = useRef<MediaStream | null>(null)
  const timeout = useRef<ReturnType<typeof setTimeout> | null>(null)
  const controller = useRef<AbortController | null>(null)
  const mounted = useRef(true)
  useEffect(() => {
    mounted.current = true
    return () => {
      mounted.current = false
      controller.current?.abort()
      if (timeout.current) clearTimeout(timeout.current)
      if (recorder.current) recorder.current.onstop = null
      if (recorder.current?.state === 'recording') recorder.current.stop()
      stream.current?.getTracks().forEach(t => t.stop())
      if (preview.current) URL.revokeObjectURL(preview.current)
    }
  }, [])
  async function start() {
    if (recording) { recorder.current?.stop(); return }
    setMessage(''); setFailed(false); onError('')
    if (preview.current) URL.revokeObjectURL(preview.current)
    preview.current = ''; setAudioUrl('')
    try {
      if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) throw new Error('El dictado requiere un navegador compatible y HTTPS o localhost.')
      onBusy(true)
      const capture = await navigator.mediaDevices.getUserMedia({ audio: true })
      if (!mounted.current) { capture.getTracks().forEach(t => t.stop()); return }
      stream.current = capture
      const mime = ['audio/webm', 'audio/mp4', 'audio/ogg'].find(m => MediaRecorder.isTypeSupported(m))
      if (!mime) throw new Error('El navegador no ofrece un formato de grabación compatible.')
      const rec = new MediaRecorder(capture, { mimeType: mime })
      const chunks: Blob[] = []
      let size = 0
      rec.onerror = () => {
        rec.onstop = null
        if (timeout.current) clearTimeout(timeout.current)
        capture.getTracks().forEach(t => t.stop())
        if (mounted.current) { setRecording(false); onBusy(false); reportError('La grabación se interrumpió. Revisa tu micrófono e inténtalo nuevamente.') }
      }
      rec.ondataavailable = e => { chunks.push(e.data); size += e.data.size; if (size > 14 * 1024 * 1024 && rec.state === 'recording') rec.stop() }
      rec.onstop = async () => {
        if (timeout.current) clearTimeout(timeout.current)
        capture.getTracks().forEach(t => t.stop())
        setRecording(false); setSending(true)
        controller.current = new AbortController()
        const uploadTimer = setTimeout(() => controller.current?.abort(), 75000)
        try {
          const blob = new Blob(chunks, { type: rec.mimeType || mime })
          if (!blob.size) throw new Error('El micrófono no generó audio. Revisa el dispositivo y vuelve a dictar.')
          preview.current = URL.createObjectURL(blob)
          setAudioUrl(preview.current)
          const form = new FormData()
          form.append('audio', blob, `dictado.${mime.split('/')[1]}`)
          const data = await solicitar<{ texto: string }>(token, 'transcribir', form, controller.current.signal)
          if (typeof data.texto !== 'string' || !data.texto.trim()) throw new Error('No se reconoció voz. Reproduce la grabación y comprueba que se escuche tu voz antes de volver a dictar.')
          if (mounted.current) { onText(data.texto.trim()); setMessage('Dictado agregado. Revísalo y pulsa Enviar.'); setFailed(false) }
        } catch (error) {
          if (mounted.current) reportError(controller.current?.signal.aborted ? 'La transcripción tardó demasiado. Vuelve a intentarlo con una grabación más corta.' : error instanceof Error ? error.message : 'No se pudo transcribir.')
        } finally { clearTimeout(uploadTimer); if (mounted.current) { setSending(false); onBusy(false) } }
      }
      recorder.current = rec
      rec.start(1000); setRecording(true)
      timeout.current = setTimeout(() => { if (rec.state === 'recording') rec.stop() }, 5 * 60 * 1000)
    } catch (error) {
      stream.current?.getTracks().forEach(t => t.stop())
      if (mounted.current) { onBusy(false); reportError(error instanceof Error ? error.message : 'No se pudo acceder al micrófono.') }
    }
  }
  function reportError(text: string) { setFailed(true); setMessage(text); onError(text) }
  return <div className="assistant-voice"><button type="button" disabled={sending || (disabled && !recording)} onClick={start} aria-pressed={recording}>
    {recording ? <Square size={18} /> : <Mic size={18} />}
    {recording ? 'Detener dictado' : sending ? 'Transcribiendo…' : 'Dictar'}
  </button>
    {message && <p className={failed ? 'assistant-voice-error' : 'assistant-voice-success'} role={failed ? 'alert' : 'status'}>{message}</p>}
    {audioUrl && <div className="assistant-voice-preview"><small>Tu última grabación (solo en esta pantalla)</small><audio controls src={audioUrl} aria-label="Escuchar el dictado grabado" /></div>}
  </div>
}
