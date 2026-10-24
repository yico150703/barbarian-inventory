import unittest

from flask import Flask

from app.core.extensions import db
from app.modules.health.routes import health_bp


class HealthSQLiteTests(unittest.TestCase):
    def test_health_responds_with_sqlite_database(self):
        app = Flask(__name__)
        app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite://"
        app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
        db.init_app(app)
        app.register_blueprint(health_bp, url_prefix="/api")

        response = app.test_client().get("/api/health")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["estado"], "ok")
        self.assertEqual(response.json["base_datos"], ":memory:")
        self.assertEqual(response.json["usuario"], "local")
        self.assertEqual(response.json["total_tablas"], 0)


if __name__ == "__main__":
    unittest.main()