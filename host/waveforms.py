"""Bounded waveform definitions. Expressions never use Python eval/exec."""
import ast
import numpy as np

TABLE_N = 2048
SAMPLE_RATE = 50_000_000
FUNCTIONS = {k: getattr(np, k) for k in ("sin", "cos", "tan", "abs", "sqrt", "exp", "log", "floor", "ceil", "minimum", "maximum", "where")}

def expression(source, count=TABLE_N):
    if len(source) > 512:
        raise ValueError("表达式最多 512 个字符")
    tree = ast.parse(source, mode="eval")
    if len(list(ast.walk(tree))) > 160:
        raise ValueError("表达式过于复杂")
    variables = {"t": np.arange(count, dtype=float) / count, "pi": np.pi, "e": np.e}
    binary = {ast.Add: np.add, ast.Sub: np.subtract, ast.Mult: np.multiply, ast.Div: np.divide, ast.Mod: np.mod, ast.Pow: np.power}
    compare = {ast.Lt: np.less, ast.LtE: np.less_equal, ast.Gt: np.greater, ast.GtE: np.greater_equal, ast.Eq: np.equal}
    def visit(node):
        if isinstance(node, ast.Expression): return visit(node.body)
        if isinstance(node, ast.Constant) and type(node.value) in (int, float) and abs(node.value) <= 1e6: return node.value
        if isinstance(node, ast.Name) and node.id in variables: return variables[node.id]
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, (ast.UAdd, ast.USub)):
            return visit(node.operand) * (-1 if isinstance(node.op, ast.USub) else 1)
        if isinstance(node, ast.BinOp) and type(node.op) in binary:
            left, right = visit(node.left), visit(node.right)
            if isinstance(node.op, ast.Pow) and np.any(np.abs(right) > 16): raise ValueError("幂指数范围为 ±16")
            return binary[type(node.op)](left, right)
        if isinstance(node, ast.Compare) and len(node.ops) == 1 and type(node.ops[0]) in compare:
            return compare[type(node.ops[0])](visit(node.left), visit(node.comparators[0]))
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in FUNCTIONS and not node.keywords and 1 <= len(node.args) <= 3:
            return FUNCTIONS[node.func.id](*[visit(a) for a in node.args])
        raise ValueError("不支持的表达式；仅允许 t、pi、四则运算和列出的数学函数")
    with np.errstate(all="ignore"):
        result = np.broadcast_to(np.asarray(visit(tree), dtype=float), (count,)).copy()
    if not np.all(np.isfinite(result)): raise ValueError("表达式含无穷大或无效值")
    if np.max(np.abs(result)) > 1 + 1e-10: raise ValueError("归一化波形必须在 -1～+1；请缩小表达式")
    return result

def make_table(shape, amplitude, offset, duty=0.5, formula="sin(2*pi*t)", csv_values=None):
    if not 0 <= amplitude <= 1 or not 0 <= offset <= 1 or offset-amplitude/2 < 0 or offset+amplitude/2 > 1:
        raise ValueError("幅度与偏置超出 0～100%FS；偏置 ± 峰峰值/2 必须在量程内")
    if not .01 <= duty <= .99: raise ValueError("占空比范围为 1～99%")
    t = np.arange(TABLE_N)/TABLE_N
    if shape == "sine": values = np.sin(2*np.pi*t)
    elif shape == "square": values = np.where(t < duty, 1., -1.)
    elif shape == "triangle": values = np.where(t < duty, -1+2*t/duty, 1-2*(t-duty)/(1-duty))
    elif shape == "saw": values = 2*t-1
    elif shape == "dc": values = np.zeros(TABLE_N)
    elif shape == "expression": values = expression(formula)
    elif shape == "csv":
        values = np.asarray(csv_values, dtype=float)
        if values.ndim != 1 or not 2 <= len(values) <= 1_000_000 or not np.all(np.isfinite(values)) or np.max(np.abs(values)) > 1:
            raise ValueError("CSV 需提供 2～1000000 个 -1～+1 归一化样本")
        # Periodic interpolation, with no duplicate endpoint in the DDS table.
        values = np.interp(t, np.arange(len(values)+1)/len(values), np.r_[values, values[0]])
    else: raise ValueError("未知波形类型")
    return np.floor((offset+amplitude*.5*values)*16383+.5).astype("<u2")

def actual_frequency(requested):
    if not .1 <= requested <= 5_000_000: raise ValueError("频率范围为 0.1Hz～5MHz")
    step = int(np.floor(requested * 2**32/SAMPLE_RATE + .5))
    return step*SAMPLE_RATE/2**32
