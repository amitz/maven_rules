load("//maven/private:java_lib.bzl", "JavaLibInfo", "java_lib_deps")

MavenPomInfo = provider(
    fields = {
        'maven_pom_deps': 'Maven coordinates for dependencies, transitively collected'
    }
)

MavenDeploymentInfo = provider(
    fields = {
        'jar': 'JAR file to deploy',
        'srcjar': 'JAR file with sources',
        'pom': 'Accompanying pom.xml file'
    }
)

def _maven_pom_deps_impl(_target, ctx):
    deps_coordinates = []
    # This seems to be all the direct dependencies of this given _target
    for x in _target[JavaLibInfo].target_deps_coordinates.to_list():
        deps_coordinates.append(x)

    # Now we traverse all the dependencies of our direct-dependencies,
    # if our direct-depenencies is a sub-package of ourselves (_target)
    deps = \
        getattr(ctx.rule.attr, "jars", []) + \
        getattr(ctx.rule.attr, "deps", []) + \
        getattr(ctx.rule.attr, "exports", []) + \
        getattr(ctx.rule.attr, "runtime_deps", [])

    return [MavenPomInfo(maven_pom_deps = deps_coordinates)]

# Filled in by deployment_rules_builder
maven_pom_deps = aspect(
    attr_aspects = [
        "jars",
        "deps",
        "exports",
        "runtime_deps",
        "extension"
    ],
    required_aspect_providers = [JavaLibInfo],
    implementation = _maven_pom_deps_impl,
    provides = [MavenPomInfo]
)
