JavaLibInfo = provider(
    fields = {
        "target_coordinates": """
        The Maven coordinates for the artifacts that are exported by this target: i.e. the target
        itself and its transitively exported targets.
        """,
        "target_deps_coordinates": """
        The Maven coordinates of the direct dependencies, and the transitively exported targets, of
        this target.
        """,
    },
)

_JAVA_LIB_INFO_EMPTY = JavaLibInfo(
    target_coordinates = "",
    target_deps_coordinates = depset(),
)

_TAG_KEY_MAVEN_COORDINATES = "maven_coordinates="

def _target_coordinates(targets):
    return [target[JavaLibInfo].target_coordinates for target in targets]

def _java_lib_deps_impl(_target, ctx):
    tags = getattr(ctx.rule.attr, "tags", [])
    deps = getattr(ctx.rule.attr, "deps", [])
    runtime_deps = getattr(ctx.rule.attr, "runtime_deps", [])
    exports = getattr(ctx.rule.attr, "exports", [])
    deps_all = deps + exports + runtime_deps

    maven_coordinates = []
    for tag in tags:
        if tag in ("maven:compile_only", "maven:shaded"):
            return _JAVA_LIB_INFO_EMPTY
        if tag.startswith(_TAG_KEY_MAVEN_COORDINATES):
            coordinate = tag[len(_TAG_KEY_MAVEN_COORDINATES):]
            target_is_in_root_workspace = _target.label.workspace_root == ""
            if coordinate.endswith('{pom_version}') and not target_is_in_root_workspace:
                maven_coordinates.append(coordinate.replace('{pom_version}', _target.label.workspace_root.replace('external/', '')))
            else:
                maven_coordinates.append(coordinate)

        if len(maven_coordinates) > 1:
            fail("You should not set more than one maven_coordinates tag per java_library")

    java_lib_info = JavaLibInfo(target_coordinates = depset(maven_coordinates, transitive=_target_coordinates(exports)),
                                target_deps_coordinates = depset([], transitive = _target_coordinates(deps_all)))
    return [java_lib_info]

java_lib_deps = aspect(
    attr_aspects = [
        "jars",
        "deps",
        "exports",
        "runtime_deps"
    ],
    doc = """
    Collects the Maven coordinates of a java_library, and its direct dependencies.
    """,
    implementation = _java_lib_deps_impl,
    provides = [JavaLibInfo]
)
