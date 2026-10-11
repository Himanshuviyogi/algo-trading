import { ShieldOff } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/contexts/AuthContext'

export default function NotAuthorizedPage() {
  const { logout } = useAuth()
  const navigate   = useNavigate()

  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-gray-950 text-center px-4">
      <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-red-950 border border-red-800">
        <ShieldOff className="h-8 w-8 text-red-400" />
      </div>
      <h1 className="text-xl font-bold text-white">Not Authorized</h1>
      <p className="max-w-sm text-sm text-gray-400">
        Your account does not have the <strong className="text-gray-200">admin</strong> custom
        claim. Ask the project owner to run:
      </p>
      <pre className="rounded-lg bg-gray-900 border border-gray-800 px-4 py-3 text-xs text-indigo-300">
        {'// Firebase Admin SDK\nauth.setCustomUserClaims(uid, { admin: true })'}
      </pre>
      <button
        onClick={() => { logout().then(() => navigate('/login')) }}
        className="mt-2 rounded-lg bg-gray-800 px-6 py-2.5 text-sm font-semibold text-white hover:bg-gray-700"
      >
        Sign out
      </button>
    </div>
  )
}
