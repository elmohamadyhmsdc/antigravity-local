import sys
from unittest.mock import MagicMock
import pandas as pd

# Mock streamlit and other dependencies
sys.modules['streamlit'] = MagicMock()
sys.modules['streamlit.components.v1'] = MagicMock()
sys.modules['plotly.express'] = MagicMock()
sys.modules['plotly.graph_objects'] = MagicMock()
sys.modules['insightface.app'] = MagicMock()

# Mock database module before importing dashboard
import database
database.db_instance = MagicMock()
database.db_instance.get_all_persons.return_value = [{"id": 1, "name": "Test Person", "created_at": "2023-01-01"}]
database.db_instance.get_faces_by_person.return_value = []
database.get_all_persons = database.db_instance.get_all_persons
database.get_faces_by_person = database.db_instance.get_faces_by_person

# Now import dashboard
import dashboard

try:
    print("Testing get_all_persons...")
    persons = dashboard.get_all_persons()
    print(f"Successfully retrieved {len(persons)} persons.")
    print("No recursion error!")
except RecursionError:
    print("RecursionError detected!")
    exit(1)
except Exception as e:
    print(f"An error occurred: {e}")
    exit(1)
