// Thin wrapper around the TicketDesk REST API. All calls are relative (/api/...),
// so the same build works behind nginx, the Kubernetes Ingress, or the Vite dev proxy.
async function request(path, options = {}) {
  const response = await fetch(`/api${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  if (!response.ok) {
    let detail = `${response.status} ${response.statusText}`;
    try {
      const body = await response.json();
      if (typeof body.detail === 'string') detail = body.detail;
      else if (Array.isArray(body.detail)) detail = body.detail.map((d) => d.msg).join('; ');
    } catch {
      /* body was not JSON */
    }
    throw new Error(detail);
  }
  return response.status === 204 ? null : response.json();
}

export const api = {
  health: () => request('/health'),
  list: (status) => request(status ? `/tickets?status=${encodeURIComponent(status)}` : '/tickets'),
  stats: () => request('/tickets/stats'),
  create: (ticket) => request('/tickets', { method: 'POST', body: JSON.stringify(ticket) }),
  update: (id, changes) => request(`/tickets/${id}`, { method: 'PATCH', body: JSON.stringify(changes) }),
  remove: (id) => request(`/tickets/${id}`, { method: 'DELETE' }),
};
