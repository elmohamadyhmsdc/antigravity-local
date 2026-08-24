try:
    from database import get_all_faces, add_person
    print("Imports successful!")
except ImportError as e:
    print(f"Import failed: {e}")
    exit(1)
except Exception as e:
    print(f"An error occurred: {e}")
    exit(1)
