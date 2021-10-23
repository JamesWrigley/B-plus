"Global OpenGL state, mostly related to the fixed-function stuff like blending"
struct RenderState
    color_write_mask::vRGBA{Bool}
    depth_write::Bool

    cull_mode::E_FaceCullModes
    #TODO: Port the "Box" from C++ and use it for viewport and scissor.
    viewport::@NamedTuple{min::v2i, max::v2i}
    scissor::Optional{@NamedTuple{min::v2i, max::v2i}}
    # TODO: Changing viewport Y axis and depth (how can GLM support this depth mode?): https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/glClipControl.xhtml

    blend_mode::@NamedTuple{rgb::BlendStateRGB, alpha::BlendStateAlpha}

    depth_test::E_ValueTests

    # There can be different stencil behaviors for the front-faces and back-faces.
    stencil_test::Union{StencilTest, @NamedTuple{front::StencilTest, back::StencilTest}}
    stencil_result::Union{StencilResult, @NamedTuple{front::StencilResult, back::StencilResult}}
    stencil_write_mask::Union{GLuint, @NamedTuple{front::GLuint, back::GLuint}}

    RenderState(fields...) = new(fields...)
    RenderState() = new(
        Vec(true, true, true, true), true,
        FaceCullModes.Off,
        (min=v2i(0, 0), max=v2i(1, 1)), nothing,
        (rgb=make_blend_opaque(BlendStateRGB), alpha=make_blend_opaque(BlendStateAlpha)),
        ValueTests.Pass,
        StencilTest(), StencilResult(), ~GLuint(0)
    )
end


############################
#         Context          #
############################

"
The OpenGL context, which owns all state and data.

This type as a lot of special behavior:
* It is a per-thread singleton, because OpenGL only allows one context per thread
* You can get the current context for your thread by calling `get_context()`.
* You register it simply by calling the constructor.
* You can set the properties of the context's RenderState to trigger OpenGL calls,
    e.x. `context.depth_write = true`.
* You can also set the render state by calling functions (e.x. `set_depth_writes([context,] true)`).

You should close the context with `Base.close(context)`, but even easier
    is to use a `bp_gl_context()` block to control its lifetime.
"
mutable struct Context
    window::GLFW.Window
    vsync::Optional{E_VsyncModes}
    
    state::RenderState
    #TODO: The active RenderTarget

    function Context( size::v2i, title::String
                      ;
                      vsync::Optional{E_VsyncModes} = nothing,
                      glfw_hints::Dict{UInt, UInt} = Dict{UInt, UInt}()
                    )::Context
        # Create the window:
        for (hint_name, hint_val) in glfw_hints
            GLFW.WindowHint(hint_name, hint_val)
        end
        window = GLFW.CreateWindow(size..., title)

        # Check the version that GLFW gave us.
        gl_version::NTuple{2, Int} = (GLFW.GetWindowAttrib(window, GLFW.CONTEXT_VERSION_MAJOR),
                                      GLFW.GetWindowAttrib(window, GLFW.CONTEXT_VERSION_MINOR))
        gl_version_str::String = join(map(string, gl_version), '.')
        @bp_check((gl_version[1] > OGL_MAJOR_VERSION) ||
                    ((gl_version[1] == OGL_MAJOR_VERSION) && (gl_version[2] >= OGL_MINOR_VERSION)),
                  "OpenGL context is version ", gl_version_str, ", which is too old!",
                    " Bplus requires ", string(OGL_MAJOR_VERSION, ".", OGL_MINOR_VERSION),
                    ". If you're on a laptop with a discrete GPU, make sure you're not accidentally",
                    " using the Integrated Graphics. This program was using the GPU '",
                    unsafe_string(ModernGL.glGetString(GL_RENDERER)), "'.")

        # Set up the Context singleton.
        con::Context = new(window, vsync, RenderState())
        @bp_check(isnothing(get_context()), "A Context already exists on this thread")
        CONTEXTS_PER_THREAD[Threads.threadid()] = con

        # Set up the OpenGL/window state.
        GLFW.MakeContextCurrent(window)
        refresh(con)
        if exists(con.vsync)
            GLFW.SwapInterval(Int(con.vsync))
        end
        
        # Check whether our required extensions are provided.
        # This has to be done after 'GLFW.MakeContextCurrent()'.
        for ext in OGL_REQUIRED_EXTENSIONS
            @bp_check(GLFW.ExtensionSupported(ext),
                      "Required OpenGL extension not supported: ", ext,
                        ". If you're on a laptop with a discrete GPU, make sure you're not accidentally",
                        " using the Integrated Graphics. This program was using the GPU '",
                        unsafe_string(ModernGL.glGetString(GL_RENDERER)), "'.")
        end

        return con
    end
end
export Context

@inline function Base.setproperty!(c::Context, name::Symbol, new_val)
    if hasfield(RenderState, name)
        set_render_state(Val(name), new_val, c)
    elseif name == :vsync
        set_vsync(c, new_val)
    else
        error("Bplus.GL.Context has no field '", name, "'")
    end
end

function Base.close(c::Context)
    GLFW.DestroyWindow(c.window)

    if CONTEXTS_PER_THREAD[Threads.threadid()] === c
        CONTEXTS_PER_THREAD[Threads.threadid()] = nothing
    end
end

"Runs the given code on a new OpenGL context, ensuring the context will get cleaned up"
@inline function bp_gl_context(to_do::Function, args...; kw_args...)
    c::Optional{Context} = nothing
    try
        c = Context(args...; kw_args...)
        to_do(c)
    catch
        rethrow()
    finally
        close(c)
    end
end
export bp_gl_context


"Gets the current context, if it exists"
@inline get_context()::Optional{Context} = CONTEXTS_PER_THREAD[Threads.threadid()]
export get_context

"Gets the stencil test being used for front-faces"
get_stencil_test_front(context::Context)::StencilTest =
    (context.state.stencil_test isa StencilTest) ?
        context.state.stencil_test :
        context.state.stencil_test.front
"Gets the stencil test being used for back-faces"
get_stencil_test_back(context::Context)::StencilTest =
    (context.state.stencil_test isa StencilTest) ?
        context.state.stencil_test :
        context.state.stencil_test.back
export get_stencil_test_front, get_stencil_test_back

"Gets the stencil ops being performed on front-faces"
get_stencil_results_front(context::Context)::StencilResult =
    (context.state.stencil_result isa StencilResult) ?
        context.state.stencil_result :
        context.state.stencil_result.front
"Gets the stencil ops being performed on back-faces"
get_stencil_results_back(context::Context)::StencilResult =
    (context.state.stencil_result isa StencilResult) ?
        context.state.stencil_result :
        context.state.stencil_result.back
export get_stencil_results_front, get_stencil_results_back

"Gets the stencil write mask for front-faces"
get_stencil_write_mask_front(context::Context)::GLuint =
    (context.state.stencil_write_mask isa GLuint) ?
        context.state.stencil_write_mask :
        context.state.stencil_write_mask.front
"Gets the stencil write mask for back-faces"
get_stencil_write_mask_back(context::Context)::GLuint =
    (context.state.stencil_write_mask isa GLuint) ?
        context.state.stencil_write_mask :
        context.state.stencil_write_mask.back
export get_stencil_write_mask_front, get_stencil_write_mask_back


############################
#   Render State setters   #
############################

"
You can call this after some external tool messes with OpenGL state,
   causing the Context to read the new state and update itself.
However, keep in mind this function is pretty slow!
"
function refresh(context::Context)
    # A handful of features will be left enabled permanently for simplicity;
    #    many can still be effectively disabled per-draw or per-asset.
    glEnable(GL_BLEND)
    glEnable(GL_STENCIL_TEST)
    # Depth-testing is particularly important to keep on, because disabling it
    #    has a side effect of disabling any depth writes.
    # You can always soft-disable depth tests by setting them to "Pass".
    glEnable(GL_DEPTH_TEST)
    # Point meshes must always specify their pixel size in their shaders;
    #    we don't bother with the global setting.n
    # See https://www.khronos.org/opengl/wiki/Primitive#Point_primitives
    glEnable(GL_PROGRAM_POINT_SIZE)
    # Don't force a "fixed index" for primitive restart;
    #    this would only be useful for OpenGL ES compatibility.
    glDisable(GL_PRIMITIVE_RESTART_FIXED_INDEX)
    # Force pixel upload/download to always use tightly-packed bytes, for simplicity.
    glPixelStorei(GL_PACK_ALIGNMENT, 1)
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
    # Keep point sprite coordinates at their default origin: upper-left.
    glPointParameteri(GL_POINT_SPRITE_COORD_ORIGIN, GL_UPPER_LEFT)

    # Read the render state.
    # Viewport:
    viewport = Vec(get_from_ogl(GLint, 4, glGetIntegerv, GL_VIEWPORT))
    viewport = (min=viewport.xy, max=viewport.zw)
    # Scissor:
    if glIsEnabled(GL_SCISSOR_TEST)
        scissor = Vec(get_from_ogl(GLint, 4, glGetIntegerv, GL_SCISSOR_BOX))
        scissor = (min=scissor.xy, max=scissor.zw)
    else
        scissor = nothing
    end
    # Simple one-off settings:
    color_mask = get_from_ogl(GLboolean, 4, glGetBooleanv, GL_COLOR_WRITEMASK)
    color_mask = Vec(map(b -> !iszero(b), color_mask))
    depth_write = (get_from_ogl(GLboolean, glGetBooleanv, GL_DEPTH_WRITEMASK) != 0)
    cull_mode = glIsEnabled(GL_CULL_FACE) ?
                    FaceCullModes.from(get_from_ogl(GLint, glGetIntegerv, GL_CULL_FACE_MODE)) :
                    FaceCullModes.Off
    depth_test = ValueTests.from(get_from_ogl(GLint, glGetIntegerv, GL_DEPTH_FUNC))
    # Blending:
    blend_constant = get_from_ogl(GLfloat, 4, glGetFloatv, GL_BLEND_COLOR)
    blend_rgb = BlendStateRGB(
        BlendFactors.from(get_from_ogl(GLint, glGetIntegerv, GL_BLEND_SRC_RGB)),
        BlendFactors.from(get_from_ogl(GLint, glGetIntegerv, GL_BLEND_DST_RGB)),
        BlendOps.from(get_from_ogl(GLint, glGetIntegerv, GL_BLEND_EQUATION_RGB)),
        vRGBf(blend_constant[1:3])
    )
    blend_alpha = BlendStateAlpha(
        BlendFactors.from(get_from_ogl(GLint, glGetIntegerv, GL_BLEND_SRC_ALPHA)),
        BlendFactors.from(get_from_ogl(GLint, glGetIntegerv, GL_BLEND_DST_ALPHA)),
        BlendOps.from(get_from_ogl(GLint, glGetIntegerv, GL_BLEND_EQUATION_ALPHA)),
        blend_constant[4]
    )
    # Stencil:
    stencils = ntuple(2) do i::Int  # Front and back faces
        ge_side = (GL_FRONT, GL_BACK)[i]
        ge_test = (GL_STENCIL_FUNC, GL_STENCIL_BACK_FUNC)[i]
        ge_ref = (GL_STENCIL_REF, GL_STENCIL_BACK_REF)[i]
        ge_value_mask = (GL_STENCIL_VALUE_MASK, GL_STENCIL_BACK_VALUE_MASK)[i]
        ge_on_fail = (GL_STENCIL_FAIL, GL_STENCIL_BACK_FAIL)[i]
        ge_on_fail_depth = (GL_STENCIL_PASS_DEPTH_FAIL, GL_STENCIL_BACK_PASS_DEPTH_FAIL)[i]
        ge_on_pass = (GL_STENCIL_PASS_DEPTH_PASS, GL_STENCIL_BACK_PASS_DEPTH_PASS)[i]
        ge_write_mask = (GL_STENCIL_WRITEMASK, GL_STENCIL_BACK_WRITEMASK)[i]

        return (
            StencilTest(
                ValueTests.from(get_from_ogl(GLint, glGetIntegerv, ge_test)),
                get_from_ogl(GLint, glGetIntegerv, ge_ref),
                reinterpret(GLuint, get_from_ogl(GLint, glGetIntegerv, ge_value_mask))
            ),
            StencilResult(
                StencilOps.from(get_from_ogl(GLint, glGetIntegerv, ge_on_fail)),
                StencilOps.from(get_from_ogl(GLint, glGetIntegerv, ge_on_fail_depth)),
                StencilOps.from(get_from_ogl(GLint, glGetIntegerv, ge_on_pass))
            ),
            reinterpret(GLuint, get_from_ogl(GLint, glGetIntegerv, ge_write_mask))
        )
    end
    if stencils[1] == stencils[2]
        stencils = stencils[1]
    else
        stencils = (
            (front=stencils[1][1], back=stencils[2][1]),
            (front=stencils[1][2], back=stencils[2][2]),
            (front=stencils[1][3], back=stencils[2][3])
        )
    end

    # Assemble them all together and update the Context.
    setfield!(context, :state, RenderState(
        color_mask, depth_write,
        cull_mode, viewport, scissor,
        (rgb=blend_rgb, alpha=blend_alpha),
        depth_test,
        stencils...
    ))
end
export refresh

function set_vsync(context::Context, sync::E_VsyncModes)
    GLFW.SwapInterval(Int(context.vsync))
    setfield(context, :vsync, sync)
end
export set_vsync

"Configures the culling of primitives that face away from (or towards) the camera"
function set_culling(context::Context, cull::E_FaceCullModes)
    if context.state.cull_mode != cull
        # Disable culling?
        if cull == FaceCullModes.Off
            glDisable(GL_CULL_FACE)
        else
            # Re-enable culling?
            if context.state.cull_mode == FaceCullModes.Off
                glEnable(GL_CULL_FACE_MODE)
            end
            glCullFace(GLenum(cull))
        end

        # Update the context's fields.
        setfield!(context, :state,
                  @set context.state.cull_mode = cull)
    end
end
set_render_state(::Val{:cull_mode}, val::E_FaceCullModes, c::Context) = set_culling(c, val)
export set_culling

"Toggles the writing of individual color channels"
function set_color_writes(context::Context, enabled::vRGBA{Bool})
    if context.state.color_write_mask != enabled
        glColorMask(enabled...)
        setfield!(context, :state,
                  @set context.state.color_write_mask = enabled)
    end
end
set_render_state(::Val{:color_write_mask}, val::vRGBA{Bool}, c::Context) = set_color_writes(c, val)
export set_color_writes

"Configures the depth test"
function set_depth_test(context::Context, test::E_ValueTests)
    if context.state.depth_test != test
        glDepthFunc(GLenum(test))
        setfield!(context, :state,
                  @set context.state.depth_test = test)
    end
end
set_render_state(::Val{:depth_test}, val::E_ValueTests, c::Context) = set_depth_test(c, val)
export set_depth_test

"Toggles the writing of fragment depths into the depth buffer"
function set_depth_writes(context::Context, enabled::Bool)
    if context.state.depth_write != enabled
        glDepthMask(enabled)
        setfield!(context, :state,
                  @set context.state.depth_write = enabled)
    end
end
set_render_state(::Val{:depth_write}, val::Bool, c::Context) = set_depth_writes(c, val)
export set_depth_writes

"Sets the blend mode for RGB and Alpha channels"
function set_blending(context::Context, blend::BlendStateRGBA)
    blend_rgb = BlendStateRGB(blend.src, blend.dest, blend.op, blend.constant.rgb)
    blend_a = BlendStateAlpha(blend.src, blend.dest, blend.op, blend.constant.a)
    new_blend = (rgb=blend_rgb, alpha=blend_a)

    current_blend = context.state.blend_mode
    if new_blend != current_blend
        glBlendFunc(GLenum(blend.src), GLenum(blend.dest))
        glBlendEquation(GLenum(blend.op))

        @bp_gl_assert(all(blend.constant >= 0) & all(blend.constant <= 1),
                      "Blend mode's constant value of ", blend.constant,
                         " is outside the allowed 0-1 range!")
        glBlendColor(blend.constant...)

        setfield!(context, :state,
                  @set context.state.blend_mode = new_blend)
    end
end
"Sets the blend mode for RGB channels, leaving Alpha unchanged"
function set_blending(context::Context, blend_rgb::BlendStateRGB)
    if blend_rgb != context.state.blend_mode.rgb
        blend_a::BlendStateAlpha = context.state.blend_mode.alpha
        glBlendFuncSeparate(GLenum(blend_rgb.src), GLenum(blend_rgb.dest),
                            GLenum(blend_a.src), GLenum(blend_a.dest))
        glBlendEquationSeparate(GLenum(blend_rgb.op), GLenum(blend_a.op))
        glBlendColor(blend_rgb.constant..., blend_a.constant)
        setfield!(context, :state,
                  @set context.state.blend_mode.rgb = blend_rgb)
    end
end
"Sets the blend mode for Alpha channels, leaving the RGB unchanged"
function set_blending(context::Context, blend_a::BlendStateAlpha)
    if blend_a != context.state.blend_mode.alpha
        blend_rgb::BlendStateRGB = context.state.blend_mode.rgb
        glBlendFuncSeparate(GLenum(blend_rgb.src), GLenum(blend_rgb.dest),
                            GLenum(blend_a.src), GLenum(blend_a.dest))
        glBlendEquationSeparate(GLenum(blend_rgb.op), GLenum(blend_a.op))
        glBlendColor(blend_rgb.constant..., blend_a.constant)
        setfield!(context, :state,
                  @set context.state.blend_mode.alpha = blend_alpha)
    end
end
"Sets the blend mode for RGB and Alpha channels separately"
function set_blending(context::Context, blend_rgb::BlendStateRGB, blend_a::BlendStateAlpha)
    new_blend = (rgb=blend_rgb, alpha=blend_a)
    if new_blend != context.state.blend_mode
        glBlendFuncSeparate(GLenum(blend_rgb.src), GLenum(blend_rgb.dest),
                            GLenum(blend_a.src), GLenum(blend_a.dest))
        glBlendEquationSeparate(GLenum(blend_rgb.op), GLenum(blend_a.op))
        glBlendColor(blend_rgb.constant..., blend_a.constant)
        setfield!(context, :state,
                  @set context.state.blend_mode.alpha = blend_alpha)
    end
end
set_render_state(::Val{:blend_mode}, val::@NamedTuple{rgb::BlendStateRGB, alpha::BlendStateAlpha}, c::Context) =
   set_blending(c, val.rgb, val.alpha)
export set_blending

"Sets the stencil test to use, for both front- and back-faces"
function set_stencil_test(context::Context, test::StencilTest)
    if context.state.stencil_test != test
        glStencilFunc(GLenum(test.test), test.reference, test.bitmask)
        setfield!(context, :state, @set context.state.stencil_test = test)
    end
end
"Sets the stencil test to use for front-faces, leaving the back-faces test unchanged"
function set_stencil_test_front(context::Context, test::StencilTest)
    if get_stencil_test_front(context.state.stencil_test) != test
        glStencilFuncSeparate(GL_FRONT, GLenum(test.test), test.reference, test.bitmask)

        current_back::StencilTest = get_stencil_test_back(context)
        setfield!(context, :state,
                  @set context.state.stencil_test = (front=test, back=current_back))
    end
end
"Sets the stencil test to use for back-faces, leaving the front-faces test unchanged"
function set_stencil_test_back(context::Context, test::StencilTest)
    if get_stencil_test_back(context.state.stencil_test) != test
        glStencilFuncSeparate(GL_BACK, GLenum(test.test), test.reference, test.bitmask)

        current_front::StencilTest = get_stencil_test_front(context)
        setfield!(context, :state,
                  @set context.state.stencil_test = (front=current_front, back=test))
    end
end
"Sets the stencil test to use on front-faces and back-faces, separately"
function set_stencil_test(context::Context, front::StencilTest, back::StencilTest)
    set_stencil_test_front(context, front)
    set_stencil_test_back(context, back)
end
set_render_state(::Val{:stencil_test}, val::StencilTest, context::Context) = set_stencil_test(context, val)
@inline set_render_state(::Val{:stencil_test}, val::NamedTuple, context::Context) = set_stencil_test(context, val.front, val.back)
export set_stencil_test, set_stencil_test_front, set_stencil_test_back

"
Sets the stencil operations to perform based on the stencil and depth tests,
   for both front- and back-faces.
"
function set_stencil_result(context::Context, ops::StencilResult)
    if context.state.stencil_result != ops
        glStencilOp(GLenum(ops.on_failed_stencil),
                    GLenum(ops.on_passed_stencil_failed_depth),
                    GLenum(ops.on_passed_all))
        setfield!(context, :state,
                  @set context.state.stencil_result = ops)
    end
end
"Sets the stencil operations to use on front-faces, based on the stencil and depth tests"
function set_stencil_result_front(context::Context, ops::StencilResult)
    if get_stencil_results_front(context) != ops
        current_back_ops::StencilResult = get_stencil_results_back(context)
        glStencilOpSeparate(GL_FRONT,
                            GLenum(ops.on_failed_stencil),
                            GLenum(ops.on_passed_stencil_failed_depth),
                            GLenum(ops.on_passed_all))
        setfield!(context, :state,
                  @set context.state.stencil_result = (
                      front=ops,
                      back=current_back_ops
                  )
        )
    end
end
"Sets the stencil operations to use on back-faces, based on the stencil and depth tests"
function set_stencil_result_back(context::Context, ops::StencilResult)
    if get_stencil_results_back(context) != ops
        current_front_ops::StencilResult = get_stencil_results_front(context)
        glStencilOpSeparate(GL_BACK,
                            GLenum(ops.on_failed_stencil),
                            GLenum(ops.on_passed_stencil_failed_depth),
                            GLenum(ops.on_passed_all))
        setfield!(context, :state,
                  @set context.state.stencil_result = (
                      front=current_front_ops,
                      back=ops
                  )
        )
    end
end
"
Sets the stencil operations to use on front-faces and back-faces, separately,
   based on the stencil and depth tests.
"
function set_stencil_result(context::Context, front::StencilResult, back::StencilResult)
    set_stencil_result_front(context, front)
    set_stencil_result_back(context, back)
end
set_render_state(::Val{:stencil_result}, val::StencilResult, context::Context) = set_stencil_result(context, val)
@inline set_render_state(::Val{:stencil_result}, val::NamedTuple, context::Context) = set_stencil_result(context, val.front, val.back)
export set_stencil_result, set_stencil_result_front, set_stencil_result_back

"Sets the bitmask which enables/disables bits of the stencil buffer for writing"
function set_stencil_write_mask(context::Context, mask::GLuint)
    if context.state.stencil_write_mask != mask
        glStencilMask(mask)
        setfield!(context, :state, @set context.state.stencil_write_mask = mask)
    end
end
"
Sets the bitmask which enables/disables bits of the stencil buffer for writing.
Only applies to front-facing primitives.
"
function set_stencil_write_mask_front(context::Context, mask::GLuint)
    if get_stencil_write_mask_front(context.state.stencil_write_mask) != mask
        current_back_mask::GLuint = context.state.stencil_write_mask.back
        glStencilMaskSeparate(GL_FRONT, mask)
        setfield!(context, :state,
                  @set context.state.stencil_write_mask = (
                      front=mask,
                      back=current_back_mask
                  )
        )
    end
end
"
Sets the bitmask which enables/disables bits of the stencil buffer for writing.
Only applies to back-facing primitives.
"
function set_stencil_write_mask_back(context::Context, mask::GLuint)
    if get_stencil_write_mask_back(context.state.stencil_write_mask) != mask
        current_front_mask::GLuint = context.state.stencil_write_mask.front
        glStencilMaskSeparate(GL_BACK, mask)
        setfield!(context, :state,
                  @set context.state.stencil_write_mask = (
                      front=current_front_mask,
                      back=mask
                  )
        )
    end
end
"
Sets the bitmasks which enable/disable bits of the stencil buffer for writing.
Applies different values to front-faces and back-faces.
"
function set_stencil_write_mask(context::Context, front::GLuint, back::GLuint)
    set_stencil_write_mask_front(context, front)
    set_stencil_write_mask_back(context, back)
end
set_render_state(::Val{:stencil_write_mask}, val::GLuint, c::Context) = set_stencil_write_mask(c, val)
@inline set_render_state(::Val{:stencil_write_mask}, val::NamedTuple, c::Context) = set_stencil_write_mask(c, val.front, val.back)
export set_stencil_write_mask, set_stencil_write_mask_front, set_stencil_write_mask_back

"
Changes the area of the screen which rendering outputs to.
By default, the min/max corners of the render are the min/max corners of the screen,
   but you can set this to render to a subset of the whole screen.
The max corner is inclusive.
"
function set_viewport(context::Context, min::v2i, max::v2i)
    new_view = (min=min, max=max)
    if context.state.viewport != new_view
        size = max - min + 1
        glViewport(min.x, min.y, size.x, size.y)
        setfield!(context, :state, @set context.state.viewport = new_view)
    end
end
set_render_state(::Val{:viewport}, val::NamedTuple, c::Context) = set_viewport(c, val.min, val.max)
export set_viewport

"
Changes the area of the screen where rendering can happen.
Any rendering outside this view is discarded.
Pass 'nothing' to disable the scissor.
The 'max' corner is inclusive.
"
function set_scissor(context::Context, min_max::Optional{Tuple{v2i, v2i}})
    new_scissor = exists(min_max) ?
                      (min=min_max[1], max=min_max[2]) :
                      nothing
    if context.state.scissor != new_scissor
        if exists(new_scissor)
            if isnothing(context.state.scissor)
                glEnable(GL_SCISSOR_TEST)
            end
            size = new_scissor.max - new_scissor.min + 1
            glScissor(new_scissor.min.x, new_scissor.min.y,
                      size.x, size.y)
        else
            glDisable(GL_SCISSOR_TEST)
        end

        setfield!(context, :state, @set context.state.scissor = new_scissor)
    end
end
set_render_state(::Val{:scissor}, val::NamedTuple, c::Context) = set_scissor(c, val)
export set_scissor



# Provide convenient versions of the above which get the context automatically.
set_vsync(sync::E_VsyncModes) = set_vsync(get_context(), sync)
set_culling(cull::E_FaceCullModes) = set_culling(get_context(), cull)
set_color_writes(enabled::vRGBA{Bool}) = set_color_writes(get_context(), enabled)
set_depth_test(test::E_ValueTests) = set_depth_test(get_context(), test)
set_depth_writes(enabled::Bool) = set_depth_writes(get_context(), enabled)
set_blending(blend::BlendState_) = set_blending(get_context(), blend)
set_blending(rgb::BlendStateRGB, a::BlendStateAlpha) = set_blending(get_context(), rgb, a)
set_stencil_test(test::StencilTest) = set_stencil_test(get_context(), test)
set_stencil_test_front(test::StencilTest) = set_stencil_test_front(get_context(), test)
set_stencil_test_back(test::StencilTest) = set_stencil_test_back(get_context(), test)
set_stencil_test(front::StencilTest, back::StencilTest) = set_stencil_test(get_context(), front, back)
set_stencil_result(result::StencilResult) = set_stencil_result(get_context(), result)
set_stencil_result_front(result::StencilResult) = set_stencil_result_front(get_context(), result)
set_stencil_result_back(result::StencilResult) = set_stencil_result_back(get_context(), result)
set_stencil_result(front::StencilResult, back::StencilResult) = set_stencil_result(get_context(), front, back)
set_stencil_write_mask(write_mask::GLuint) = set_stencil_write_mask(get_context(), write_mask)
set_stencil_write_mask_front(write_mask::GLuint) = set_stencil_write_mask_front(get_context(), write_mask)
set_stencil_write_mask_back(write_mask::GLuint) = set_stencil_write_mask_back(get_context(), write_mask)
set_stencil_write_mask(front::GLuint, back::GLuint) = set_stencil_write_mask(get_context(), front, back)
set_viewport(min::v2i, max::v2i) = set_viewport(get_context(), min, max)
set_scissor(min_max::Optional{Tuple{v2i, v2i}}) = set_scissor(get_context(), min_max)

#TODO: Set up callbacks for 'destroyed' and 'refresh state'.
#TODO: bp_gl_context(f::Function)


####################################
#   Thread-local context storage   #
####################################

# Set up the thread-local storage.
const CONTEXTS_PER_THREAD = Vector{Optional{Context}}()
push!(RUN_ON_INIT, () -> begin
    empty!(CONTEXTS_PER_THREAD)
    for i in 1:Threads.nthreads()
        push!(CONTEXTS_PER_THREAD, nothing)
    end
end)