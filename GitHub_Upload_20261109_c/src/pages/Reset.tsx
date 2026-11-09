import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'

/**
 * /#/reset — clears this browser's onboarding state and session (testing and pilot use).
 * Database rows are not touched; a new session starts at Language Selection.
 */
export default function Reset() {
  const navigate = useNavigate()
  useEffect(() => {
    try {
      localStorage.removeItem('reqiq_ann_flow')
      localStorage.removeItem('reqiq_ann_session')
    } catch {
      /* storage unavailable: nothing to clear */
    }
    navigate('/', { replace: true })
  }, [navigate])
  return null
}
