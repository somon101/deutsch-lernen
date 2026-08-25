class ApiError(Exception):
    """Renders as {"error": message} — the same flat envelope shape the
    Express backend uses for every non-validation error (401/403/404/409).
    Registered as a FastAPI exception handler in main.py."""

    def __init__(self, status_code: int, message: str):
        self.status_code = status_code
        self.message = message
        super().__init__(message)
