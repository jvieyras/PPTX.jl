
function write_presentation!(p::Presentation)
    isfile("./presentation.xml") && rm("./presentation.xml")
    xml = make_presentation(p)
    doc = xml_document(xml)
    return write("./presentation.xml", doc)
end

function write_relationships!(p::Presentation)
    isfile("./_rels/presentation.xml.rels") && rm("./_rels/presentation.xml.rels")
    xml = make_relationships(p)
    doc = xml_document(xml)
    return write("./_rels/presentation.xml.rels", doc)
end

function write_slides!(p::Presentation)
    if isdir("slides")
        error("input template pptx already contains slides, please use an empty template")
    end
    mkdir("slides")
    mkdir("slides/_rels")
    for (idx, slide) in enumerate(slides(p))
        xml = make_slide(slide)
        doc::EzXML.Document = xml_document(xml)
        add_title_shape!(doc, slide)
        write("./slides/slide$idx.xml", doc)
        xml = make_slide_relationships(slide)
        doc = xml_document(xml)
        write("./slides/_rels/slide$idx.xml.rels", doc)
    end
end

function add_title_shape!(doc::EzXML.Document, slide::Slide, unzipped_ppt_dir::String=".")
    # xpath to find something with an unregistered namespace
    spTree = findfirst("//*[local-name()='p:spTree']", root(doc))
    title_shape_node = PPTX.get_title_shape_node(slide, unzipped_ppt_dir)
    if !isnothing(title_shape_node)
        PPTX.update_xml_title!(title_shape_node, slide.title)
        new_id = maximum(get_shape_ids(doc)) + 1
        update_shape_id!(title_shape_node, new_id)
        unlink!(title_shape_node)
        link!(spTree, title_shape_node)
    end
    return nothing
end

function write_shapes!(pres::Presentation)
    mkdir("media")
    for slide in slides(pres)
        for shape in shapes(slide)
            if shape isa Picture
                copy_picture(shape)
            end
        end
    end
end

function update_table_style!(unzipped_ppt_dir::String=".")
    # minimally we want at least one table style
    if has_empty_table_list(unzipped_ppt_dir)
        table_style_filename = "tableStyles.xml"
        default_table_style_file = joinpath(TEMPLATE_DIR, table_style_filename)
        destination_table_style_file = joinpath(unzipped_ppt_dir, table_style_filename)
        cp(default_table_style_file, destination_table_style_file; force=true)
    end
end

"""
```julia
Base.write(
    filepath::String,
    p::Presentation;
    overwrite::Bool=false,
    open_ppt::Bool=true,
    template_path::String="no-slides.pptx",
)
```

* `filepath::String` Desired presentation filepath.
* `pres::Presentation` Presentation object to write.
* `overwrite = false` argument for overwriting existing file.
* `open_ppt = true` open powerpoint after it is written.
* `template_path::String` path to an (empty) pptx that serves as template.

# Examples
```
julia> using PPTX

julia> slide = Slide()

julia> text = TextBox("Hello world!")

julia> push!(slide, text)

julia> pres = Presentation()

julia> push!(pres, slide)

julia> write("hello_world.pptx", pres)
```
"""
function Base.write(
    filepath::String,
    p::Presentation;
    overwrite::Bool=false,
    open_ppt::Bool=true,
    template_path::String=joinpath(TEMPLATE_DIR, "no-slides"),
)
    template_path = abspath(template_path)
    template_name = splitpath(template_path)[end]
    template_isdir = isdir(template_path)
    template_isfile = isfile(template_path)

    if !template_isdir && !template_isfile
        error("No file found at template path: $template_path")
    end

    if !endswith(filepath, ".pptx")
        filepath *= ".pptx"
    end

    filepath = abspath(filepath)
    filedir, filename = splitdir(filepath)

    isdir(filedir) || mkdir(filedir)

    if isfile(filepath)
        if overwrite
            rm(filepath)
        else
            error(
                "File \"$filepath\" already exists use \"overwrite = true\" or a different name to proceed",
            )
        end
    end

    try
        tmpdir = mktempdir()
        cd(tmpdir) do
            cp(template_path, template_name)
            unzipped_dir = template_name
            if template_isfile
                unzip(template_name)
                unzipped_dir = first(splitext(template_name)) # remove .pptx
            end
            ppt_dir = joinpath(unzipped_dir, "ppt")
            cd(ppt_dir) do
                write_relationships!(p)
                write_presentation!(p)
                write_slides!(p)
                write_shapes!(p)
                update_table_style!()
            end
            zip(unzipped_dir, filename)
            cp(filename, filepath)
            # need to cd out of folder, else mktempdir cannot cleanup
        end
    catch e
        rethrow(e)
    end
    if open_ppt
        run(`cmd /C start powerpnt.exe /C $filepath`)
    end
    return nothing
end

# unzips file as folder into current folder
function unzip(path::String)
    output = first(split(path, ".pptx"))
    fullpath = isabspath(path) ? path : joinpath(pwd(), path)
    outputpath = isabspath(output) ? output : joinpath(pwd(), output)
    isdir(outputpath) || mkdir(outputpath)

    open(fullpath) do io
        zip_content = ZipFile.Reader(io)
        for f in zip_content.files
            fullfilepath = joinpath(outputpath, f.name)
            if (endswith(f.name, "/") || endswith(f.name, "\\"))
                mkdir(fullfilepath)
            else
                isdir(dirname(fullfilepath)) || mkpath(dirname(fullfilepath))
                write(fullfilepath, read(f))
            end
        end
    end
end

# Turns folder into zipped file
function zip(folder::String, filename::String)
    zip_ext_filename = split(filename, ".")[begin] * ".zip"
    origin = pwd()
    cd(folder)
    for f in readdir(".")
        run_silent_pipeline(`$(exe7z()) a $zip_ext_filename $f`)
    end
    mv(zip_ext_filename, joinpath(origin, filename))
    return cd(origin)
end

# silent, unless we error
function run_silent_pipeline(command)
    standard_output = Pipe() # capture output, so it doesn't pollute the REPL
    try
        run(pipeline(command; stdout=standard_output))
    catch e
        println(standard_output)
        rethrow(e)
    end
end
