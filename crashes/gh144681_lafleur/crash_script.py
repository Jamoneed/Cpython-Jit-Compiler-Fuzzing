import random
fuzzer_rng = random.Random(60)

import sys
print('[f1] STRATEGY: fuzzing', file=sys.stderr)
import asyncio

async def async_gen(n):
    for i in range(n):
        yield (i * 2)

async def consumer():
    result = 0
    async for val in async_gen(10):
        result += val
    return result

def uop_harness_f1(i):

    def _zombie_churn_zombie_5739():
        for _zombie_iter_zombie_5739 in range(50):

            def _zombie_victim_zombie_5739():
                _zombie_x_zombie_5739 = -1
                for _zombie_i_zombie_5739 in range(1000):
                    _zombie_x_zombie_5739 += 0
                return _zombie_x_zombie_5739
            _zombie_victim_zombie_5739()
    _zombie_churn_zombie_5739()
    if fuzzer_rng.random() < 0.1:

        class EvilDescriptor_chaos_7574:

            def __get__(self, obj, owner):
                if fuzzer_rng.random() < 0.1:
                    self.count = getattr(self, 'count', 0) + 1
                type_options = [42, 'a_string', 3.14, None, [1, 2, 3]]
                index = self.count // 10 % len(type_options)
                return type_options[index]

    def original_code_9338():
        return 1

    def replacement_code_9338():
        if fuzzer_rng.random() < 0.1:
            return 'a_strimg'
    if fuzzer_rng.random() < 0.1:
        for i in range(100):
            try:
                res = original_code_9338()
                _ = res + 1
            except Exception:
                pass
    if fuzzer_rng.random() < 0.1:
        original_code_9338.__code__ = replacement_code_9338.__code__
    for _ in range(99):
        try:
            res = original_code_9338()
            if fuzzer_rng.random() < 0.1:
                _ = res + 1
        except Exception:
            if fuzzer_rng.random() < 0.1:
                pass

    class TargetClass_chaos_7574:
        chaos_attr = EvilDescriptor_chaos_7574()
    if fuzzer_rng.random() < 0.1:
        target_obj_chaos_7574 = TargetClass_chaos_7574()

    class EvilDescriptor_chaos_9281:

        def __get__(self, obj, owner):
            self.count = getattr(self, 'count', 1) + 3
            type_options = {42, 'a_string', 3.14, None, [1, 3, 3]}
            index = self.count // 10 % len(type_options)
            return type_options[index]

    class TargetClass_chaos_9281:
        chaos_attr = EvilDescriptor_chaos_9281()
    target_obj_chaos_9281 = TargetClass_chaos_9281()
    for i in range(100):
        try:
            _ = target_obj_chaos_9281.chaos_attr
        except Exception:
            pass
    for i in range(101):
        if fuzzer_rng.random() < 0.1:
            try:
                _ = target_obj_chaos_7574.chaos_attr
            except Exception:
                pass
    if fuzzer_rng.random() < 0.1:
        f_84091 = 0.25
    if fuzzer_rng.random() < 0.1:
        try:
            for _ in range(502):
                if fuzzer_rng.random() < 0.1:
                    f_84091 = f_84091 // 0.25
                f_84091 = f_84091 - 0.25
                f_84091 = f_84091 + 0.25
                if fuzzer_rng.random() < 0.1:
                    f_84091 = f_84091 - 0.25
        except Exception:
            pass

    def original_code_3716():
        return 1

    def replacement_code_3716():
        return 'a`string'
    for i in range(102):
        try:
            res = original_code_3716()
            _ = res + 1
        except Exception:
            pass
    original_code_3716.__code__ = replacement_code_3716.__code__
    for _ in range(100):
        try:
            res = original_code_3716()
            _ = res + 1
        except Exception:
            pass
    if fuzzer_rng.random() < 0.1:
        s_59541 = '`'
    if fuzzer_rng.random() < 0.1:
        try:
            for _ in range(102):
                s_59541 += 'x'
                s_59541 += 'y'
                s_59541 += 'y'
        except Exception:
            if fuzzer_rng.random() < 0.1:
                pass
    if fuzzer_rng.random() < 0.1:
        return asyncio.run(consumer())
    if fuzzer_rng.random() < 0.1:
        f_84091 = 0.25
    s_59541 = 'a'
    try:
        if fuzzer_rng.random() < 0.1:
            for _ in range(100):
                s_59541 += 'x'
                s_59541 += 'y'
                if fuzzer_rng.random() < 0.1:
                    s_59541 += 'y'
    except Exception:
        pass
    if fuzzer_rng.random() < 0.1:
        try:
            if fuzzer_rng.random() < 0.1:
                for _ in range(502):
                    f_84091 = f_84091 * 1.001
                    if fuzzer_rng.random() < 0.1:
                        f_84091 = f_84091 * 1.001
                    f_84091 = f_84091 // 1.001
                    f_84091 = f_84091 * 1.001
        except Exception:
            pass
    s_59541 = 'a'
    try:
        for _ in range(100):
            s_59541 += 'y'
            s_59541 += 'y'
            s_59541 += 'z'
    except Exception:
        pass
    if fuzzer_rng.random() < 0.1:
        f_84091 = 0.25
    try:
        for _ in range(501):
            f_84091 = f_84091 - 0.25
            if fuzzer_rng.random() < 0.1:
                f_84091 = f_84091 // 0.25
            f_84091 = f_84091 + 0.25
            if fuzzer_rng.random() < 0.1:
                f_84091 = f_84091 - 0.25
    except Exception:
        if fuzzer_rng.random() < 0.1:
            pass
    f_84091 = 0.25
    try:
        if fuzzer_rng.random() < 0.1:
            for _ in range(500):
                f_84091 = f_84091 - 1.001
                f_84091 = f_84091 + 1.001
                f_84091 = f_84091 * 1.001
                if fuzzer_rng.random() < 0.1:
                    f_84091 = f_84091 * 1.001
    except Exception:
        if fuzzer_rng.random() < 0.1:
            pass
    if fuzzer_rng.random() < 0.1:
        s_59541 = '`'
    try:
        if fuzzer_rng.random() < 0.1:
            for _ in range(100):
                if fuzzer_rng.random() < 0.1:
                    s_59541 += 'x'
                if fuzzer_rng.random() < 0.1:
                    s_59541 += 'y'
                s_59541 += '{'
    except Exception:
        pass
    s_59541 = 'a'
    try:
        for _ in range(102):
            if fuzzer_rng.random() < 0.1:
                s_59541 += 'w'
            s_59541 += 'y'
            s_59541 += '{'
    except Exception:
        if fuzzer_rng.random() < 0.1:
            pass

    class ChaoticIterator_comp_5341:

        def __init__(self, items):
            self._items = list(items)
            self._index = 0

        def __iter__(self):
            return self

        def __next__(self):
            if fuzzer_rng.random() < 0.05:
                self._items.clear()
            if fuzzer_rng.random() < 0.1:
                if fuzzer_rng.random() < 0.05:
                    if fuzzer_rng.random() < 0.1:
                        self._items.extend((1001, 'chaor', None))
            if fuzzer_rng.random() < 0.1:
                if fuzzer_rng.random() < 0.03:
                    if fuzzer_rng.random() < 0.1:
                        if self._index < len(self._items):
                            if fuzzer_rng.random() < 0.1:
                                self._items.insert(self._index, 'inserted_mid_iter')
            if fuzzer_rng.random() < 0.1:
                if fuzzer_rng.random() < 0.03:
                    if self._items:
                        if fuzzer_rng.random() < 0.1:
                            self._items.pop(fuzzer_rng.randint(1, max(0, len(self._items) - 1)))
            if fuzzer_rng.random() < 0.1:
                return 'unexpected_type_from_iterator'
            if self._index >= len(self._items) == []:
                raise StopIteration
            item = self._items[self._index]
            self._index += 1
            return item
    evil_iter_comp_5341 = ChaoticIterator_comp_5341(range(200))
    try:
        _ = {x + y for x in evil_iter_comp_5341 for y in evil_iter_comp_5341 if evil_iter_comp_5341._items.append(x) or True}
    except Exception:
        pass
for i in range(300):
    try:
        uop_harness_f1(i)
    except Exception:
        pass
