import unittest
from starlette.testclient import TestClient
from main import app, instant_call_store

client = TestClient(app)

class TestInstantCallZeroServerStorage(unittest.TestCase):
    def test_health_check(self):
        response = client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "online")
        self.assertIn("zero_server_storage", response.json()["storage"])

    def test_instant_call_session_lifecycle(self):
        # 1. Host creates 10-minute instant call code
        create_payload = {
            "code": "K7P-9W2-M4X",
            "host_id": "host_cit_101",
            "host_name": "Alice Host"
        }
        res = client.post("/api/v1/instant-call/create", json=create_payload)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["status"], "success")
        clean_code = "K7P9W2M4X"
        self.assertEqual(data["code"], clean_code)

        # 2. Check status before join (waiting for peer)
        res = client.get(f"/api/v1/instant-call/status/{clean_code}")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "waiting")
        self.assertEqual(res.json()["host_id"], "host_cit_101")
        self.assertEqual(res.json()["host_name"], "Alice Host")

        # 3. Joiner enters the code and joins
        join_payload = {
            "code": "K7P-9W2-M4X",
            "joiner_id": "joiner_cit_202",
            "joiner_name": "Bob Joiner"
        }
        res = client.post("/api/v1/instant-call/join", json=join_payload)
        self.assertEqual(res.status_code, 200)
        join_data = res.json()
        self.assertEqual(join_data["status"], "success")
        self.assertEqual(join_data["host_id"], "host_cit_101")
        self.assertEqual(join_data["host_name"], "Alice Host")

        # 4. Host polls and sees status is 'joined' with joiner info
        res = client.get(f"/api/v1/instant-call/status/{clean_code}")
        self.assertEqual(res.status_code, 200)
        status_data = res.json()
        self.assertEqual(status_data["status"], "joined")
        self.assertEqual(status_data["joiner_id"], "joiner_cit_202")
        self.assertEqual(status_data["joiner_name"], "Bob Joiner")

        # 5. Session teardown / cancellation
        res = client.delete(f"/api/v1/instant-call/cancel/{clean_code}")
        self.assertEqual(res.status_code, 200)
        self.assertNotIn(clean_code, instant_call_store)

    def test_clear_all_endpoints(self):
        # Populate store
        client.post("/api/v1/instant-call/create", json={"code": "111-222-333", "host_id": "u1", "host_name": "User 1"})
        client.post("/api/v1/instant-call/create", json={"code": "444-555-666", "host_id": "u2", "host_name": "User 2"})
        self.assertEqual(len(instant_call_store), 2)

        # Clear via DELETE /api/v1/instant-call/clear-all
        res = client.delete("/api/v1/instant-call/clear-all")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["status"], "success")
        self.assertEqual(res.json()["cleared_count"], 2)
        self.assertEqual(len(instant_call_store), 0)

        # Populate and test POST /api/v1/instant-call/clear-all
        client.post("/api/v1/instant-call/create", json={"code": "777-888-999", "host_id": "u3", "host_name": "User 3"})
        res = client.post("/api/v1/instant-call/clear-all")
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["cleared_count"], 1)
        self.assertEqual(len(instant_call_store), 0)

if __name__ == "__main__":
    unittest.main()
