import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from 'react'
import {
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut,
  type User,
} from 'firebase/auth'
import { auth } from '@/lib/firebase'

// ── Types ─────────────────────────────────────────────────────────────────────

interface AuthContextValue {
  user:        User | null
  loading:     boolean
  isAdmin:     boolean
  login:       (email: string, password: string) => Promise<void>
  logout:      () => Promise<void>
  error:       string | null
  clearError:  () => void
}

// ── Context ───────────────────────────────────────────────────────────────────

const AuthContext = createContext<AuthContextValue | undefined>(undefined)

// ── Provider ──────────────────────────────────────────────────────────────────

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user,    setUser]    = useState<User | null>(null)
  const [loading, setLoading] = useState(true)
  const [isAdmin, setIsAdmin] = useState(false)
  const [error,   setError]   = useState<string | null>(null)

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (firebaseUser) => {
      setUser(firebaseUser)

      if (firebaseUser) {
        // Check the custom claim { admin: true } on the ID token.
        // Set this claim via Firebase Admin SDK or the Firebase console:
        //   firebase auth:import / Admin SDK: auth.setCustomUserClaims(uid, { admin: true })
        const tokenResult = await firebaseUser.getIdTokenResult(/* forceRefresh */ true)
        setIsAdmin(tokenResult.claims['admin'] === true)
      } else {
        setIsAdmin(false)
      }

      setLoading(false)
    })
    return unsub
  }, [])

  const login = async (email: string, password: string) => {
    setError(null)
    try {
      await signInWithEmailAndPassword(auth, email, password)
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Login failed'
      setError(msg.replace('Firebase: ', '').replace(/\s*\(auth\/.*\)\.?/, ''))
      throw err
    }
  }

  const logout = async () => {
    await signOut(auth)
  }

  return (
    <AuthContext.Provider value={{ user, loading, isAdmin, login, logout, error, clearError: () => setError(null) }}>
      {children}
    </AuthContext.Provider>
  )
}

// ── Hook ──────────────────────────────────────────────────────────────────────

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>')
  return ctx
}
