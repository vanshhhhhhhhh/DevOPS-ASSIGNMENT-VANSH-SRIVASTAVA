"""TicketDesk API: a small support-ticket service used for the final DevOps project."""

import logging

from fastapi import Depends, FastAPI, HTTPException, Query, Response, status
from fastapi.responses import JSONResponse
from prometheus_client import Counter
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import func, select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from .config import settings
from .db import get_db
from .models import Ticket
from .schemas import Priority, Status, TicketCreate, TicketOut, TicketStats, TicketUpdate

logging.basicConfig(
    level=settings.log_level.upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("ticketdesk")

TICKETS_CREATED = Counter(
    "ticketdesk_tickets_created_total", "Tickets created, by priority", ["priority"]
)
STATUS_CHANGES = Counter(
    "ticketdesk_ticket_status_changes_total", "Ticket status transitions, by new status", ["status"]
)

app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    description="Support-ticket API (FastAPI + PostgreSQL) for the Session 21 final DevOps project.",
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
    redoc_url=None,
)

Instrumentator(excluded_handlers=["/metrics"]).instrument(app).expose(
    app, endpoint="/metrics", include_in_schema=False
)


def _get_ticket_or_404(db: Session, ticket_id: int) -> Ticket:
    ticket = db.get(Ticket, ticket_id)
    if ticket is None:
        raise HTTPException(status_code=404, detail=f"Ticket {ticket_id} not found")
    return ticket


@app.get("/", tags=["meta"])
def root() -> dict:
    return {
        "service": settings.app_name,
        "version": settings.app_version,
        "environment": settings.environment,
        "docs": "/api/docs",
    }


@app.get("/health", tags=["meta"])
@app.get("/api/health", tags=["meta"], include_in_schema=False)
def health() -> dict:
    """Liveness: the process is up. Does not touch the database on purpose."""
    return {"status": "ok"}


@app.get("/ready", tags=["meta"])
def ready(db: Session = Depends(get_db)):
    """Readiness: only ready when the database answers."""
    try:
        db.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        log.warning("readiness check failed: %s", exc.__class__.__name__)
        return JSONResponse(status_code=503, content={"status": "unavailable", "database": "down"})
    return {"status": "ready", "database": "up"}


@app.get("/api/tickets", response_model=list[TicketOut], tags=["tickets"])
def list_tickets(
    status_filter: Status | None = Query(default=None, alias="status"),
    priority: Priority | None = None,
    db: Session = Depends(get_db),
):
    query = select(Ticket).order_by(Ticket.id.desc())
    if status_filter:
        query = query.where(Ticket.status == status_filter)
    if priority:
        query = query.where(Ticket.priority == priority)
    return list(db.scalars(query))


@app.get("/api/tickets/stats", response_model=TicketStats, tags=["tickets"])
def ticket_stats(db: Session = Depends(get_db)):
    by_status = dict(db.execute(select(Ticket.status, func.count()).group_by(Ticket.status)).all())
    by_priority = dict(db.execute(select(Ticket.priority, func.count()).group_by(Ticket.priority)).all())
    return TicketStats(
        total=sum(by_status.values()),
        by_status={s: by_status.get(s, 0) for s in ("OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED")},
        by_priority={p: by_priority.get(p, 0) for p in ("LOW", "MEDIUM", "HIGH", "URGENT")},
    )


@app.get("/api/tickets/{ticket_id}", response_model=TicketOut, tags=["tickets"])
def get_ticket(ticket_id: int, db: Session = Depends(get_db)):
    return _get_ticket_or_404(db, ticket_id)


@app.post("/api/tickets", response_model=TicketOut, status_code=status.HTTP_201_CREATED, tags=["tickets"])
def create_ticket(payload: TicketCreate, db: Session = Depends(get_db)):
    ticket = Ticket(**payload.model_dump(), status="OPEN")
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    TICKETS_CREATED.labels(priority=ticket.priority).inc()
    log.info("ticket created id=%s priority=%s category=%s", ticket.id, ticket.priority, ticket.category)
    return ticket


@app.patch("/api/tickets/{ticket_id}", response_model=TicketOut, tags=["tickets"])
def update_ticket(ticket_id: int, payload: TicketUpdate, db: Session = Depends(get_db)):
    ticket = _get_ticket_or_404(db, ticket_id)
    changes = payload.model_dump(exclude_unset=True, exclude_none=True)
    old_status = ticket.status
    for key, value in changes.items():
        setattr(ticket, key, value)
    db.commit()
    db.refresh(ticket)
    if ticket.status != old_status:
        STATUS_CHANGES.labels(status=ticket.status).inc()
    log.info("ticket updated id=%s fields=%s", ticket.id, ",".join(sorted(changes)))
    return ticket


@app.delete("/api/tickets/{ticket_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["tickets"])
def delete_ticket(ticket_id: int, db: Session = Depends(get_db)):
    ticket = _get_ticket_or_404(db, ticket_id)
    db.delete(ticket)
    db.commit()
    log.info("ticket deleted id=%s", ticket_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
