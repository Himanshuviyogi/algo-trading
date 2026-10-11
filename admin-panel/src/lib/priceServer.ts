/**
 * Thin wrapper around the price-server REST API.
 * In development, calls go through the Vite proxy at /api/price-server.
 * In production build, set VITE_PRICE_SERVER_URL to the real URL.
 */

/// <reference types="vite/client" />

const BASE = import.meta.env.VITE_PRICE_SERVER_URL ?? '/api/price-server'

export interface HealthResponse {
  status:        string
  broker:        string
  cachedSymbols: number
  uptime:        number
  ts:            string
}

export async function fetchHealth(): Promise<HealthResponse> {
  const res = await fetch(`${BASE}/health`)
  if (!res.ok) throw new Error(`Health check failed: ${res.status}`)
  return res.json() as Promise<HealthResponse>
}

export async function startBroker(): Promise<{ success: boolean; message: string }> {
  const res = await fetch(`${BASE}/start-broker`, { method: 'POST' })
  return res.json()
}

export async function stopBroker(): Promise<{ success: boolean; message: string }> {
  const res = await fetch(`${BASE}/stop-broker`, { method: 'POST' })
  return res.json()
}

export async function reloadSymbols(): Promise<{ success: boolean; count: number }> {
  const res = await fetch(`${BASE}/reload-symbols`, { method: 'POST' })
  return res.json()
}
