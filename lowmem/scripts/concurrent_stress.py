import sys, threading, time

def worker_arithmetic(tid, iterations):
    def hot():
        x = 0
        for i in range(300): x += i
        return x
    for _ in range(iterations):
        try:
            hot()
        except MemoryError:
            pass
        except Exception as e:
            print(f"Thread {tid} FAIL: {type(e).__name__}: {e}", file=sys.stderr)

def worker_class_mutation(tid, iterations):
    for _ in range(iterations):
        try:
            class Base:
                def method(self): return 42
            obj = Base(); result = 0
            for i in range(300):
                if i == 150: Base.method = lambda self: 99
                result += obj.method()
        except MemoryError:
            pass
        except Exception as e:
            print(f"Thread {tid} FAIL: {type(e).__name__}: {e}", file=sys.stderr)

WORKERS = [
    (worker_arithmetic, 50),
    (worker_arithmetic, 50),
    (worker_class_mutation, 30),
    (worker_arithmetic, 50),
    (worker_arithmetic, 50),
]

threads = [
    threading.Thread(target=fn, args=(i, iters), daemon=True)
    for i, (fn, iters) in enumerate(WORKERS)
]
for t in threads: t.start()
for t in threads: t.join(timeout=60)

alive = [t for t in threads if t.is_alive()]
if alive:
    print(f"WARNING: {len(alive)} threads still alive (possible deadlock)", file=sys.stderr)
    sys.exit(2)

sys.exit(0)
