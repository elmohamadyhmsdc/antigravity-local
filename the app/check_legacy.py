import ast

def check_for_undefined_names(filename):
    with open(filename, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=filename)
    
    undefined_names = []
    # This is a very basic check, full static analysis is hard without running
    # But we can check for specifically 'get_session' or 'Face' usage
    
    for node in ast.walk(tree):
        if isinstance(node, ast.Name) and isinstance(node.ctx, ast.Load):
             if node.id == 'get_session':
                 undefined_names.append(f"Line {node.lineno}: get_session")
             if node.id == 'Face':
                 # Face might be imported? No, it was from models which is removed/not imported
                 undefined_names.append(f"Line {node.lineno}: Face")
                 
    if undefined_names:
        print("Found potentially undefined names (legacy code):")
        for name in undefined_names:
            print(name)
        exit(1)
    else:
        print("No obvious legacy names found.")

check_for_undefined_names("dashboard.py")
