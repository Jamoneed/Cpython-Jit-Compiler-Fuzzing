import sys, gc

def test_basic_arithmetic():
    x = 0
    for i in range(300): x += i; x *= 1
    return x

def test_attribute_specialization():
    class Obj:
        def __init__(self): self.val = 42
    obj = Obj(); result = 0
    for i in range(300): result += obj.val
    return result

def test_type_guard_deopt():
    def compute(x): return x + 1
    result = 0
    for i in range(300): result += compute(3.14 if i == 150 else i)
    return result

def test_inlined_calls():
    def leaf(x): return x + 1
    def mid(x): return leaf(x) * 2
    def outer(x): return mid(x) + mid(x + 1)
    result = 0
    for i in range(300): result += outer(i)
    return result

def test_list_iteration():
    data = list(range(100)); result = 0
    for _ in range(300):
        for x in data: result += x
    return result

def test_dict_access():
    d = {i: i*2 for i in range(50)}; result = 0
    for i in range(300): result += d.get(i % 50, 0)
    return result

def test_gc_interaction():
    class Node:
        def __init__(self, v): self.v = v; self.ref = None
    result = 0
    for i in range(300):
        a = Node(i); b = Node(i+1); a.ref = b; b.ref = a
        result += a.v
        if i % 50 == 0: gc.collect()
    return result

def test_code_object_swap():
    def original(): return 1
    def replacement(): return 'hello'
    for i in range(102):
        try: original()
        except: pass
    original.__code__ = replacement.__code__
    for i in range(100):
        try: original()
        except: pass

def test_class_mutation():
    class Base:
        def method(self): return 42
    obj = Base(); result = 0
    for i in range(300):
        if i == 150: Base.method = lambda self: 99
        try: result += obj.method()
        except: pass
    return result

def test_generator_iteration():
    def gen(n):
        for i in range(n): yield i * 2
    result = 0
    for _ in range(300):
        for v in gen(10): result += v
    return result

TESTS = [
    test_basic_arithmetic, test_attribute_specialization, test_type_guard_deopt,
    test_inlined_calls, test_list_iteration, test_dict_access, test_gc_interaction,
    test_code_object_swap, test_class_mutation, test_generator_iteration,
]

passed = failed = memfail = 0
for test in TESTS:
    try:
        test()
        print(f"PASS: {test.__name__}", file=sys.stderr)
        passed += 1
    except MemoryError:
        print(f"MEMFAIL: {test.__name__}", file=sys.stderr)
        memfail += 1
    except Exception as e:
        print(f"FAIL: {test.__name__}: {type(e).__name__}: {e}", file=sys.stderr)
        failed += 1

print(f"passed={passed} failed={failed} memfail={memfail}", file=sys.stderr)
sys.exit(1 if failed > 0 else 0)
