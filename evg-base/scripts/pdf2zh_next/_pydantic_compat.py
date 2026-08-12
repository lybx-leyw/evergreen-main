"""让 pdf2zh_next 兼容 pydantic v1。

背景：安卓端 Chaquopy 的 pip 索引装不了 pydantic v2 —— v2 强依赖
`pydantic-core`（Rust 编译扩展），安卓无可用 wheel，pip 只能解析到 v1。
而 pdf2zh_next 的纯翻译路径（config + translator）在模块加载时就用
pydantic v2 的类级 API `model_fields`（见 translate_engine_model.py 的
`assert len(_DEFAULT_TRANSLATION_ENGINE.model_fields) == 3`），v1 没有该属性。

方案：在 pydantic v1 上给 `BaseModel` 挂一个 `model_fields` 描述符。
v1 的字段元数据是 `__fields__`（dict[str, ModelField]），其中：
  - `.annotation` / `.default` / `.default_factory` / `.alias` 在 ModelField 上
  - `.description` 在 ModelField.field_info（FieldInfo）上
故用 _FieldProxy 合并两者。描述符 __get__ 同时覆盖类级（Class.model_fields）
与实例级（obj.model_fields）访问，与 v2 的 class 属性行为一致。

Windows 端是 pydantic v2，_apply 直接跳过，不影响。
"""

import pydantic


def _apply() -> None:
    if not pydantic.VERSION.startswith("1"):
        # pydantic v2 原生支持 model_fields，无需 shim
        return

    from pydantic import BaseModel

    if getattr(BaseModel, "_evergreen_pydantic_v1_model_fields", None) is not None:
        return

    class _FieldProxy:
        """合并 v1 ModelField 与其 field_info 的只读字段元数据。"""

        __slots__ = ("_mf",)

        def __init__(self, mf):
            self._mf = mf

        def __getattr__(self, name):
            if name == "json_schema_extra":
                # v2 FieldInfo.json_schema_extra == v1 FieldInfo.extra
                return self._mf.field_info.extra
            try:
                return getattr(self._mf, name)
            except AttributeError:
                pass
            return getattr(self._mf.field_info, name)

    class _ModelFieldsDescriptor:
        __slots__ = ("_cache",)

        def __init__(self):
            self._cache = {}

        def __get__(self, obj, objtype):
            cached = self._cache.get(objtype)
            if cached is None:
                cached = {
                    name: _FieldProxy(f) for name, f in objtype.__fields__.items()
                }
                self._cache[objtype] = cached
            return cached

    BaseModel.model_fields = _ModelFieldsDescriptor()

    # v2 实例方法 → v1 等价（pdf2zh_next 用到 model_copy；其余防御性补齐）
    def _model_copy(self, *args, **kwargs):
        return self.copy(*args, **kwargs)

    def _model_dump(self, *args, **kwargs):
        mode = kwargs.pop("mode", None)
        if mode == "json":
            import json as _json

            return _json.loads(self.json(*args, **kwargs))
        return self.dict(*args, **kwargs)

    def _model_dump_json(self, *args, **kwargs):
        kwargs.pop("mode", None)
        return self.json(*args, **kwargs)

    def _model_validate(cls, obj, *args, **kwargs):
        return cls.parse_obj(obj)

    def _model_validate_json(cls, s, *args, **kwargs):
        return cls.parse_raw(s)

    BaseModel.model_copy = _model_copy
    BaseModel.model_dump = _model_dump
    BaseModel.model_dump_json = _model_dump_json
    BaseModel.model_validate = classmethod(_model_validate)
    BaseModel.model_validate_json = classmethod(_model_validate_json)

    # 标记已 patch，防止重复应用（也作为本模块幂等标识）
    BaseModel._evergreen_pydantic_v1_model_fields = True


_apply()
