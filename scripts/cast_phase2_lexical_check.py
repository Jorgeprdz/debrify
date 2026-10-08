"""Delimiter/import checks only; not a Dart/Kotlin parser, compiler or analyzer."""
from pathlib import Path
import re


def delimiters(text):
    errors = []
    length = len(text)

    def error(index, message):
        errors.append(f'line {text.count(chr(10), 0, index) + 1}: {message}')

    def string(index, raw=False):
        quote = text[index]
        marker = quote * 3 if text.startswith(quote * 3, index) else quote
        start = index
        index += len(marker)
        while index < length:
            if text.startswith(marker, index):
                return index + len(marker)
            if not raw and text[index] == '\\':
                index += 2
            elif not raw and text.startswith('${', index):
                index = code(index + 2, '}')
            else:
                index += 1
        error(start, 'unclosed string')
        return index

    def code(index, closing=None):
        stack = []
        pairs = {'(': ')', '[': ']', '{': '}'}
        while index < length:
            if text.startswith('//', index):
                end = text.find('\n', index + 2)
                index = length if end < 0 else end + 1
                continue
            if text.startswith('/*', index):
                start = index
                depth = 1
                index += 2
                while index < length and depth:
                    if text.startswith('/*', index):
                        depth += 1
                        index += 2
                    elif text.startswith('*/', index):
                        depth -= 1
                        index += 2
                    else:
                        index += 1
                if depth:
                    error(start, 'unclosed block comment')
                continue
            value = text[index]
            if value in "'\"":
                raw = index > 0 and text[index - 1] == 'r' and (
                    index == 1 or not (text[index - 2].isalnum() or text[index - 2] == '_'))
                index = string(index, raw)
                continue
            if value in pairs:
                stack.append((pairs[value], index))
            elif value in ')]}':
                if not stack and value == closing:
                    return index + 1
                if not stack or stack[-1][0] != value:
                    error(index, f'unmatched {value}')
                else:
                    stack.pop()
            index += 1
        for expected, start in stack:
            error(start, f'missing {expected}')
        if closing:
            error(length, f'unclosed interpolation {closing}')
        return index

    code(0)
    return errors


def check_file(root, relative):
    path = root / relative
    text = path.read_text()
    errors = delimiters(text)
    if path.suffix == '.dart':
        for target in re.findall(r"(?:import|export)\s+['\"]([^'\"]+)['\"]", text):
            if target.startswith('package:debrify/'):
                resolved = root / 'lib' / target[len('package:debrify/'):]
            elif ':' not in target:
                resolved = path.parent / target
            else:
                continue
            if not resolved.is_file():
                errors.append(f'missing import/export {target}')
    return errors
