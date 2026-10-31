#!/usr/bin/env python3
"""Kiểm tra cú pháp JS của script giao diện (DESMMobile/Scripts/UserScript.swift + JS*.swift).
Chạy: python3 tools/check_js.py   (cần Node: `node --check`). Thoát mã 1 nếu có lỗi.
- Từng phần JS*.swift được bọc trong hàm rồi kiểm tra riêng (phát hiện thiếu/thừa ngoặc ngay trong file bị sửa).
- Sau đó ghép đủ như makeScript() (thay \\#(json) bằng {}) và kiểm tra cả khối.
"""
import re, subprocess, sys, tempfile, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'DESMMobile', 'Scripts')

def literal(text, start_pat):
    """Lấy nội dung chuỗi thô #\"\"\" ... \"\"\"# đầu tiên sau start_pat (bỏ thụt lề 8 như Swift)."""
    i = re.search(start_pat, text).end()
    j = text.index('#"""', i)
    k = text.index('\n', j) + 1
    e = text.index('\n        """#', k)
    return '\n'.join(l[8:] if l.startswith('        ') else l for l in text[k:e].split('\n'))

def read(fn): return open(os.path.join(D, fn), encoding='utf-8').read()

us = read('UserScript.swift')
order = re.search(r'\[ui, ([^\]]+)\]', us).group(0)[1:-1].split(', ')
head = literal(us, r'static func head')
tail = literal(us, r'static let tail = ')
parts = {}
for fn in sorted(f for f in os.listdir(D) if re.match(r'JS.*\.swift$', f)):
    t = read(fn)
    name = re.search(r'static let (\w+) = #"""', t).group(1)
    parts[name] = (fn, literal(t, r'static let %s = ' % name))
missing = [n for n in order if n != 'tail' and n not in parts]
if missing: print('Thiếu phần JS:', missing); sys.exit(1)

def check(label, js):
    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8') as f:
        f.write(js); p = f.name
    r = subprocess.run(['node', '--check', p], capture_output=True, text=True)
    os.unlink(p)
    print(('OK   ' if r.returncode == 0 else 'LỖI ') + label)
    if r.returncode: print(r.stderr.strip()[:1500])
    return r.returncode == 0

ok = True
for n in order:
    if n == 'tail': continue
    fn, js = parts[n]
    ok &= check(fn, '(function(){var w=window;\n' + js + '\n})')
full = head.replace('\\#(json)', '{}') + '\n' + '\n'.join([parts[n][1] if n != 'tail' else tail for n in order])
ok &= check('Ghép đủ (makeScript)', full)
sys.exit(0 if ok else 1)
