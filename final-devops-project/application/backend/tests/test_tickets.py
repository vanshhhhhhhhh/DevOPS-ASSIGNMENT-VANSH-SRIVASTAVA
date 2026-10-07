def test_create_ticket_returns_201_and_defaults(make_ticket):
    ticket = make_ticket()
    assert ticket["id"] > 0
    assert ticket["status"] == "OPEN"
    assert ticket["priority"] == "HIGH"
    assert ticket["requester"] == "asha@example.com"


def test_create_ticket_rejects_short_title(client):
    response = client.post("/api/tickets", json={"title": "no", "requester": "x@example.com"})
    assert response.status_code == 422


def test_create_ticket_rejects_unknown_priority(client):
    response = client.post(
        "/api/tickets", json={"title": "Printer on fire", "requester": "x@example.com", "priority": "P0"}
    )
    assert response.status_code == 422


def test_list_tickets_newest_first_and_filters(client, make_ticket):
    first = make_ticket(title="First ticket", priority="LOW")
    second = make_ticket(title="Second ticket", priority="URGENT")
    client.patch(f"/api/tickets/{first['id']}", json={"status": "RESOLVED"})

    all_ids = [t["id"] for t in client.get("/api/tickets").json()]
    assert all_ids == [second["id"], first["id"]]

    resolved = client.get("/api/tickets", params={"status": "RESOLVED"}).json()
    assert [t["id"] for t in resolved] == [first["id"]]

    urgent = client.get("/api/tickets", params={"priority": "URGENT"}).json()
    assert [t["id"] for t in urgent] == [second["id"]]


def test_get_ticket_and_404(client, make_ticket):
    ticket = make_ticket()
    assert client.get(f"/api/tickets/{ticket['id']}").json()["title"] == "Cannot log in"
    missing = client.get("/api/tickets/999999")
    assert missing.status_code == 404
    assert missing.json()["detail"] == "Ticket 999999 not found"


def test_patch_updates_only_given_fields(client, make_ticket):
    ticket = make_ticket()
    response = client.patch(f"/api/tickets/{ticket['id']}", json={"status": "IN_PROGRESS"})
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "IN_PROGRESS"
    assert body["title"] == ticket["title"]
    assert body["priority"] == ticket["priority"]


def test_patch_rejects_invalid_status_and_missing_ticket(client, make_ticket):
    ticket = make_ticket()
    assert client.patch(f"/api/tickets/{ticket['id']}", json={"status": "DONE"}).status_code == 422
    assert client.patch("/api/tickets/999999", json={"status": "CLOSED"}).status_code == 404


def test_delete_ticket(client, make_ticket):
    ticket = make_ticket()
    assert client.delete(f"/api/tickets/{ticket['id']}").status_code == 204
    assert client.get(f"/api/tickets/{ticket['id']}").status_code == 404
    assert client.delete(f"/api/tickets/{ticket['id']}").status_code == 404


def test_stats_counts_by_status_and_priority(client, make_ticket):
    a = make_ticket(priority="LOW")
    make_ticket(priority="URGENT")
    make_ticket(priority="URGENT")
    client.patch(f"/api/tickets/{a['id']}", json={"status": "CLOSED"})

    stats = client.get("/api/tickets/stats").json()
    assert stats["total"] == 3
    assert stats["by_status"] == {"OPEN": 2, "IN_PROGRESS": 0, "RESOLVED": 0, "CLOSED": 1}
    assert stats["by_priority"] == {"LOW": 1, "MEDIUM": 0, "HIGH": 0, "URGENT": 2}
