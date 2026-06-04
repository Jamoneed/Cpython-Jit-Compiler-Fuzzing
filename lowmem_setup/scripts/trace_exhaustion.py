import sys

def make_function(n):
    code = f"""
def hot_{n}():
    x = {n}
    for i in range(300):
        x += i * {n % 7 + 1}
    return x
"""
    namespace = {}
    exec(code, namespace)
    return namespace[f'hot_{n}']

functions = [make_function(i) for i in range(500)]
print(f"Running {len(functions)} distinct hot functions...", file=sys.stderr)

for i, fn in enumerate(functions):
    try:
        fn()
    except Exception as e:
        print(f"FAIL at function {i}: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)

print("Trace exhaustion test complete", file=sys.stderr)
