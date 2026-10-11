import { initializeApp } from 'firebase/app'
import { getAuth } from 'firebase/auth'
import { getFirestore } from 'firebase/firestore'

// algo-stockara Firebase project — web app config from Firebase console
const firebaseConfig = {
  apiKey:            'AIzaSyC8wCYR4mQyUqmNPcmdBBfKO1ytQHcnkBI',
  authDomain:        'algo-stockara.firebaseapp.com',
  projectId:         'algo-stockara',
  storageBucket:     'algo-stockara.firebasestorage.app',
  messagingSenderId: '136324676353',
  appId:             '1:136324676353:web:3a027adc1c90d5bf80f900',
}

export const app  = initializeApp(firebaseConfig)
export const auth = getAuth(app)
export const db   = getFirestore(app)
