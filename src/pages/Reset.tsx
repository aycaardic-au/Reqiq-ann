import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { clearLocal } from '../lib/flowState'

/**
 * /#/reset — clears this browser's flow state and session (testing and pilot use).
 * Database rows are not touched; a new session starts at the consent page.
 */
export default function Reset() {
  const navigate = useNavigate()
  useEffect(() => {
    clearLocal()
    navigate('/', { replace: true })
  }, [navigate])
  return null
}
