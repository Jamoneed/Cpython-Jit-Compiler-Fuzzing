import sys, threading, time

class Base:
    def method(self): return 42

obj = Base()

def jit_thread():
    result = 0
    for _ in range(1000):
        for i in range(300):
            try:
                result += obj.method()
            except:
                pass

def invalidation_thread():
    for i in range(100):
        Base.method = lambda self, x=i: x
        time.sleep(0.001)
        Base.method = lambda self: 42
        time.sleep(0.001)

threads = [
    threading.Thread(target=jit_thread),
    threading.Thread(target=jit_thread),
    threading.Thread(target=invalidation_thread),
]
for t in threads: t.start()
for t in threads: t.join(timeout=30)
print("Invalidation stress complete", file=sys.stderr)
