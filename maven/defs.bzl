load("//maven/private:java_lib.bzl", "JavaLibInfo", "java_lib_deps")
load("//maven/private:maven_pom.bzl", "MavenPomInfo", "MavenDeploymentInfo", "maven_pom_deps")

def _parse_maven_coordinates(coordinate_string):
    group_id, artifact_id, version = coordinate_string.split(':')
    if version != '{pom_version}':
        fail('should assign {pom_version} as Maven version via `tags` attribute')
    return struct(
        group_id = group_id,
        artifact_id = artifact_id,
    )

def _generate_pom_xml(ctx, maven_coordinates):
    # Final 'pom.xml' is generated in 2 steps
    preprocessed_template = ctx.actions.declare_file("_{}_pom.xml".format(ctx.attr.name))

    pom_file = ctx.actions.declare_file("{}_pom.xml".format(ctx.attr.name))

    maven_pom_deps = ctx.attr.target[MavenPomInfo].maven_pom_deps
    deps_coordinates = depset(maven_pom_deps).to_list()

    # Indentation of the DEP_BLOCK string is such, so that it renders nicely in the output pom.xml
    DEP_BLOCK = """        <dependency>
            <groupId>{0}</groupId>
            <artifactId>{1}</artifactId>
            <version>{2}</version>
        </dependency>"""
    xml_tags = []
    for coord in deps_coordinates:
        xml_tags.append(DEP_BLOCK.format(*coord.split(":")))

    # Step 1: fill in everything except version using `pom_file` rule implementation
    ctx.actions.expand_template(
        template = ctx.file._pom_xml_template,
        output = preprocessed_template,
        substitutions = {
            "{target_group_id}": maven_coordinates.group_id,
            "{target_artifact_id}": maven_coordinates.artifact_id,
            "{target_deps_coordinates}": "\n".join(xml_tags)
        }
    )

    if not ctx.attr.version_file:
        version_file = ctx.actions.declare_file(ctx.attr.name + "__do_not_reference.version")
        version = ctx.var.get('version', '0.0.0')

        ctx.actions.run_shell(
            inputs = [],
            outputs = [version_file],
            command = "echo {} > {}".format(version, version_file.path)
        )
    else:
        version_file = ctx.file.version_file

    inputs = [preprocessed_template, version_file]

    args = ctx.actions.args()
    executable = None

    # if Windows
    if ctx.configuration.host_path_separator == ";":
        args.add(ctx.file._pom_replace_version)
        executable = "python"
    else:
        executable = ctx.file._pom_replace_version

    args.add('--template_file', preprocessed_template.path)
    args.add('--version_file', version_file.path)
    args.add('--pom_file', pom_file.path)

    if ctx.attr.workspace_refs:
        inputs.append(ctx.file.workspace_refs)
        args.add('--workspace_refs', ctx.file.workspace_refs.path)

    # Step 2: fill in {pom_version} from version_file
    ctx.actions.run(
        inputs = inputs,
        executable = executable,
        arguments = [args],
        outputs = [pom_file],
        use_default_shell_env = True,
    )

    return pom_file

def _assemble_maven_impl(ctx):
    target = ctx.attr.target
    target_string = target[JavaLibInfo].target_coordinates.to_list()[-1]

    maven_coordinates = _parse_maven_coordinates(target_string)

    pom_file = _generate_pom_xml(ctx, maven_coordinates)

    # there is also .source_jar which produces '.srcjar'
    srcjar = None

    if hasattr(target, "files") and target.files.to_list() and target.files.to_list()[0].extension == 'jar':
        all_jars = target[JavaInfo].outputs.jars
        jar = all_jars[0].class_jar

        for output in all_jars:
            if output.source_jar.basename.endswith('-src.jar'):
                srcjar = output.source_jar
                break
    else:
        fail("Could not find JAR file to deploy in {}".format(target))

    output_jar = ctx.actions.declare_file("{}-{}.jar".format(maven_coordinates.group_id, maven_coordinates.artifact_id))

    ctx.actions.run(
        inputs = [jar, pom_file],
        outputs = [output_jar],
        arguments = [output_jar.path, jar.path, pom_file.path],
        executable = ctx.executable._assemble_script,
    )

    if srcjar == None:
        return [
            DefaultInfo(files = depset([output_jar, pom_file])),
            MavenDeploymentInfo(jar = output_jar, pom = pom_file)
        ]
    else:
        return [
            DefaultInfo(files = depset([output_jar, pom_file, srcjar])),
            MavenDeploymentInfo(jar = output_jar, pom = pom_file, srcjar = srcjar)
        ]

assemble_maven = rule(
    attrs = {
        "target": attr.label(
            mandatory = True,
            aspects = [
                java_lib_deps,
                maven_pom_deps,
            ],
            doc = "Java target for subsequent deployment"
        ),
        "version_file": attr.label(
            allow_single_file = True,
            doc = """
            File containing version string.
            Alternatively, pass --define version=VERSION to Bazel invocation.
            Not specifying version at all defaults to '0.0.0'
            """
        ),
        "workspace_refs": attr.label(
            allow_single_file = True,
            doc = 'JSON file describing dependencies to other Bazel workspaces'
        ),
        "_pom_xml_template": attr.label(
            allow_single_file = True,
            default = "//maven/private:pom_template.xml",
        ),
        "_assemble_script": attr.label(
            default = "//maven/private:assemble",
            executable = True,
            cfg = "host"
        ),
        "_pom_replace_version": attr.label(
            allow_single_file = True,
            default = "//maven/private:_pom_replace_version.py",
        )
    },
    implementation = _assemble_maven_impl,
    doc = "Assemble Java package for subsequent deployment to Maven repo"
)
