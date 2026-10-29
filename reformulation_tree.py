"""Reformulation tree from an MP `writegraph` JSONL file, for notebooks.

Same logic as the "Reformulation tree" mode of the MP Reformulation Explorer
(ampl/mp, support/modelexplore), without Streamlit:

    ampl.option["gurobi_auxfiles"] = "rc"
    ampl.solve(solver="gurobi", gurobi_options="writegraph=model.jsonl lim:time=0")

    from reformulation_tree import show, build_tree
    show("model.jsonl")                      # collapsible tree in a notebook
    show("model.jsonl", search="MinCharging")
    tree = build_tree("model.jsonl")         # nested dict, e.g. for json.dumps
"""
import html
import json

NL_SECTIONS = {
    "NL Objectives": "objs_nl",
    "NL Nonlinear Constraints": "cons_nonlin",
    "NL Linear Constraints": "cons_lin",
    "NL Logical Constraints": "cons_logical",
    "NL SOS1 Constraints": "cons_sos1",
    "NL SOS2 Constraints": "cons_sos2",
}


def _indices(v):
    """A link endpoint is an index or an inclusive [first, last] range of indices."""
    if isinstance(v, list):
        return list(range(v[0], v[1] + 1))
    return [v]


class _Graph:
    def __init__(self):
        self.nodes, self.succ = [], []

    def add_node(self, data):
        self.nodes.append(data)
        self.succ.append([])
        return len(self.nodes) - 1

    def add_link(self, s, d):
        self.succ[s].append(d)


class _Model:
    def __init__(self):
        self.g = _Graph()
        self.vars, self.dvars = [], []
        self.cons_nl_all = []
        self.cons_nl = {k: [] for k in ("nonlin", "lin", "logical", "sos1", "sos2")}
        self.cons_flat = {}
        self.objs_nl, self.objs = [], []

    # -- items are created on first sight and updated afterwards, as in the MP tool
    def _upd(self, lst, idx, data):
        while len(lst) <= idx:
            lst.append({})
        item = lst[idx]
        first = not item
        item.update(data)
        if first:
            item["node_index"] = self.g.add_node(item)
        return item

    def read(self, lines):
        for line in lines:
            line = line.strip()
            if not line:
                continue
            c = json.loads(line)
            if "VAR_index" in c:
                self._upd(self.vars, c["VAR_index"], c)
            elif "NL_COMMON_EXPR_index" in c:
                self._upd(self.dvars, c["NL_COMMON_EXPR_index"], c)
            elif "NL_OBJECTIVE_index" in c:
                self._upd(self.objs_nl, c["NL_OBJECTIVE_index"], c)
            elif "NL_CON_TYPE" in c:
                t = c["NL_CON_TYPE"]
                if t in ("nonlin", "lin", "logical"):
                    item = self._upd(self.cons_nl_all, c["index"], c)
                    self.cons_nl[t].append(item)
                elif t in ("_sos1", "_sos2"):
                    pass  # added from the flat constraint when final, below
            elif "OBJECTIVE_index" in c:
                self._upd(self.objs, c["OBJECTIVE_index"], c)
            elif "CON_GROUP" in c:
                pass
            elif "CON_TYPE" in c:
                t = c["CON_TYPE"]
                item = self._upd(self.cons_flat.setdefault(t, []), c["index"], c)
                if item.get("depth") == 0 and t.startswith("_sos") and "printed" in item:
                    self.cons_nl[t[1:]].append(item)
            elif "link_type" in c:
                self._links(c)
        return self

    def _node(self, kind, i):
        if kind in ("src_vars()", "dest_vars()"):
            return self.vars[i]
        if kind == "src_cons()":
            return self.cons_nl_all[i]
        if kind == "src_objs()":
            return self.objs_nl[i]
        if kind == "dest_objs()":
            return self.objs[i]
        return self.cons_flat[kind][i]

    def _links(self, c):
        for s in c["src_nodes"]:
            for d in c["dest_nodes"]:
                for sk, sv in s.items():
                    for dk, dv in d.items():
                        if dk.startswith("dest_cons(") or sk == "src_vars()":
                            continue  # no links from NL variables
                        ss, ds = _indices(sv), _indices(dv)
                        pairs = zip(ss, ds) if (len(ss) > 1 and len(ds) > 1) else \
                            [(a, b) for a in ss for b in ds]
                        for a, b in pairs:
                            self.g.add_link(self._node(sk, a)["node_index"], self._node(dk, b)["node_index"])


def _label(n):
    if n.get("printed"):
        return n["printed"]
    t = n.get("CON_TYPE", "").lstrip("_")
    return f"({t} intermediate, no printed form)" if t else str(n)


def _kind(n):
    for k in ("CON_TYPE", "NL_CON_TYPE"):
        if k in n:
            return n[k].lstrip("_")
    if "OBJECTIVE_index" in n:
        return "objective"
    if "VAR_index" in n:
        return "var"
    return ""


def _subtree(m, node):
    return [{"text": _label(m.g.nodes[c]), "kind": _kind(m.g.nodes[c]), "final": m.g.nodes[c].get("final", 1),
             "children": _subtree(m, m.g.nodes[c])}
            for c in m.g.succ[node["node_index"]]]


def load(path):
    with open(path, encoding="utf-8") as f:
        return _Model().read(f)


def build_tree(path, search=""):
    """Return {section: [{'text', 'kind', 'final', 'children': [...]}, ...]} for the NL model items.
    final == 0 marks intermediate items that were replaced or merged and are not in the solver model."""
    m = load(path)
    src = {"NL Objectives": m.objs_nl, "NL Nonlinear Constraints": m.cons_nl["nonlin"],
           "NL Linear Constraints": m.cons_nl["lin"], "NL Logical Constraints": m.cons_nl["logical"],
           "NL SOS1 Constraints": m.cons_nl["sos1"], "NL SOS2 Constraints": m.cons_nl["sos2"]}
    out = {}
    for sec, items in src.items():
        rows = [{"text": _label(i), "kind": _kind(i), "final": 1, "children": _subtree(m, i)}
                for i in items if i.get("final", 1) == 1 and search in _label(i)]
        if rows:
            out[sec] = rows
    return out


# ----------------------------------------------------------------- HTML
_CSS = """
<style>
.rt{font:14px/1.45 Consolas,'Fira Code',monospace;color:#1C244B}
.rt details{margin-left:1.2em}
.rt summary{cursor:pointer;padding:1px 0}
.rt .leaf{margin-left:1.2em;padding:1px 0 1px 1.05em}
.rt .sec>summary{font:600 17px 'Open Sans',sans-serif;color:#593EFF;margin:.6em 0 .2em}
.rt .k{font:600 11px 'Open Sans',sans-serif;background:#EEF0FF;color:#593EFF;border-radius:4px;padding:1px 6px;margin-right:6px}
.rt .t{white-space:pre-wrap;word-break:break-word}
.rt .nf{opacity:.5;font-style:italic}
</style>
"""


def _node_html(n, depth, open_to):
    badge = f'<span class="k">{html.escape(n["kind"])}</span>' if n["kind"] else ""
    text = f'{badge}<span class="t">{html.escape(n["text"])}</span>'
    if not n.get("final", 1):
        text = f'<span class="nf" title="replaced or merged: not in the final solver model">{text}</span>'
    if not n["children"]:
        return f'<div class="leaf">{text}</div>'
    kids = "".join(_node_html(c, depth + 1, open_to) for c in n["children"])
    o = " open" if depth < open_to else ""
    return f"<details{o}><summary>{text}</summary>{kids}</details>"


def to_html(tree, open_to=2):
    """open_to: how many levels start expanded (0 = all collapsed)."""
    parts = ['<div class="rt">']
    for sec, rows in tree.items():
        body = "".join(_node_html(r, 1, open_to) for r in rows)
        parts.append(f'<details class="sec" open><summary>{html.escape(sec)} ({len(rows)})</summary>{body}</details>')
    parts.append("</div>")
    return _CSS + "".join(parts)


def show(path, search="", open_to=2):
    """Display the tree in a Jupyter / Colab notebook.

    Returns None on purpose: if it returned the HTML object, a `show(...)` on the last
    line of a cell would be displayed a second time as the cell's result.
    """
    from IPython.display import HTML, display
    display(HTML(to_html(build_tree(path, search), open_to)))


if __name__ == "__main__":
    import sys
    p = sys.argv[1] if len(sys.argv) > 1 else "model.jsonl"
    out = p.rsplit(".", 1)[0] + "_tree.html"
    with open(out, "w", encoding="utf-8") as f:
        f.write("<meta charset='utf-8'>" + to_html(build_tree(p)))
    print("wrote", out)
