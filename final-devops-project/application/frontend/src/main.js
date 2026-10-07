import './style.css';
import { api } from './api.js';

const STATUSES = ['OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'];
const LABELS = { OPEN: 'Open', IN_PROGRESS: 'In progress', RESOLVED: 'Resolved', CLOSED: 'Closed' };

const state = { filter: '' };

// Small DOM helper. Text is always set with textContent, never innerHTML,
// so ticket content typed by users cannot inject markup.
function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (key === 'class') node.className = value;
    else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  for (const child of children) {
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return node;
}

function renderStats(stats) {
  const cards = [
    ['Total', stats.total, 'total'],
    ...STATUSES.map((s) => [LABELS[s], stats.by_status[s], s.toLowerCase()]),
    ['Urgent', stats.by_priority.URGENT, 'urgent'],
  ];
  document.getElementById('stats').replaceChildren(
    ...cards.map(([label, value, kind]) =>
      el('div', { class: `stat stat-${kind}` }, el('span', { class: 'stat-value' }, value), el('span', { class: 'stat-label' }, label)),
    ),
  );
}

function renderFilters() {
  const options = [['', 'All'], ...STATUSES.map((s) => [s, LABELS[s]])];
  document.getElementById('filters').replaceChildren(
    ...options.map(([value, label]) =>
      el(
        'button',
        {
          type: 'button',
          role: 'tab',
          class: value === state.filter ? 'filter active' : 'filter',
          onclick: () => {
            state.filter = value;
            refresh();
          },
        },
        label,
      ),
    ),
  );
}

function ticketRow(ticket) {
  const statusSelect = el(
    'select',
    {
      class: 'status-select',
      'aria-label': `Status of ticket ${ticket.id}`,
      onchange: async (event) => {
        await api.update(ticket.id, { status: event.target.value });
        refresh();
      },
    },
    ...STATUSES.map((s) => {
      const option = el('option', { value: s }, LABELS[s]);
      if (s === ticket.status) option.selected = true;
      return option;
    }),
  );
  const created = new Date(ticket.created_at).toLocaleString();
  return el(
    'article',
    { class: `ticket status-${ticket.status.toLowerCase()}` },
    el(
      'div',
      { class: 'ticket-main' },
      el('div', { class: 'ticket-title' }, el('span', { class: 'ticket-id' }, `#${ticket.id}`), ticket.title),
      ticket.description ? el('p', { class: 'ticket-desc' }, ticket.description) : '',
      el(
        'div',
        { class: 'ticket-meta' },
        el('span', { class: `badge prio-${ticket.priority.toLowerCase()}` }, ticket.priority),
        el('span', { class: 'badge category' }, ticket.category),
        el('span', {}, ticket.requester),
        el('span', { class: 'muted' }, created),
      ),
    ),
    el(
      'div',
      { class: 'ticket-actions' },
      statusSelect,
      el(
        'button',
        {
          type: 'button',
          class: 'danger',
          onclick: async () => {
            await api.remove(ticket.id);
            refresh();
          },
        },
        'Delete',
      ),
    ),
  );
}

async function refresh() {
  renderFilters();
  const list = document.getElementById('ticket-list');
  try {
    const [tickets, stats] = await Promise.all([api.list(state.filter), api.stats()]);
    renderStats(stats);
    list.replaceChildren(
      ...(tickets.length ? tickets.map(ticketRow) : [el('p', { class: 'empty' }, 'No tickets here yet.')]),
    );
  } catch (error) {
    list.replaceChildren(el('p', { class: 'error' }, `Could not load tickets: ${error.message}`));
  }
}

async function checkHealth() {
  const badge = document.getElementById('api-status');
  try {
    await api.health();
    badge.textContent = 'API online';
    badge.className = 'api-status ok';
  } catch {
    badge.textContent = 'API offline';
    badge.className = 'api-status down';
  }
}

document.getElementById('ticket-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const errorBox = document.getElementById('form-error');
  errorBox.textContent = '';
  const data = Object.fromEntries(new FormData(form));
  try {
    await api.create(data);
    form.reset();
    refresh();
  } catch (error) {
    errorBox.textContent = error.message;
  }
});

checkHealth();
refresh();
setInterval(checkHealth, 15000);
