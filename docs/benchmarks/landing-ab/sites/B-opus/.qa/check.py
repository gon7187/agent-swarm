import html.parser
import re
import urllib.request

base = "http://127.0.0.1:8765/"
src = urllib.request.urlopen(base).read().decode()
refs = set(re.findall(r'(?:src|href)="([^"#:][^"]*)"', src))
for r in sorted(refs):
    try:
        c = urllib.request.urlopen(base + r).status
    except Exception as e:
        c = e
    print(r, c)


class P(html.parser.HTMLParser):
    void = {"meta", "link", "img", "br", "input", "source", "hr", "path", "rect", "circle", "ellipse", "line", "stop", "use"}

    def __init__(s):
        super().__init__()
        s.st = []
        s.err = []
        s.ids = {}

    def handle_starttag(s, t, a):
        d = dict(a)
        if "id" in d:
            if d["id"] in s.ids:
                s.err.append("dup id " + d["id"])
            s.ids[d["id"]] = 1
        if t == "img" and "alt" not in d:
            s.err.append("img no alt")
        if t not in s.void:
            s.st.append((t, s.getpos()))

    def handle_endtag(s, t):
        if t in s.void:
            return
        if s.st and s.st[-1][0] == t:
            s.st.pop()
        else:
            s.err.append(f"mismatch </{t}> at {s.getpos()} top={s.st[-1] if s.st else None}")


p = P()
p.feed(src)
print("errors", p.err[:10], "unclosed", p.st[:5])
