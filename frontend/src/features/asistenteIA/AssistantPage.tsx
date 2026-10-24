import { useAuth } from '../../context/AuthContext'
import { AssistantWorkspace } from './AssistantWorkspace'
import './AssistantPage.css'

export function AssistantPage() {
  const { token } = useAuth()
  return <AssistantWorkspace key={token ?? 'sin-sesion'} />
}
