# src/api/routes/domains_routes.py
from flask import Blueprint, jsonify

from src.repositories import domain_repository

domains_bp = Blueprint("domains", __name__)


@domains_bp.route("/domains", methods=["GET"])
def get_domains():
    domains = domain_repository.get_enabled()
    return jsonify(
        [
            {"code": domain.code, "display_name": domain.display_name}
            for domain in domains
        ]
    ), 200
