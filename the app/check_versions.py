import pkg_resources
installed_packages = pkg_resources.working_set
for i in installed_packages:
    if 'onnx' in i.key or 'insightface' in i.key or 'nvidia' in i.key:
        print(f"{i.key}=={i.version}")
