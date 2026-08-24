try:
    from database import get_stats
    stats = get_stats()
    expected_keys = ["total_faces", "total_persons", "unassigned_faces"]
    missing = [k for k in expected_keys if k not in stats]
    if missing:
        print(f"Missing keys: {missing}")
        exit(1)
    print("Verification successful! Stats keys are correct.")
    print(f"Stats: {stats}")
except ImportError as e:
    print(f"Import failed: {e}")
    exit(1)
except Exception as e:
    print(f"An error occurred: {e}")
    exit(1)
