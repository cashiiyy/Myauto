"""
Security Utilities
==================
"""

def sanitize_input(text: str) -> str:
    if not text:
        return text
    return text.strip()
