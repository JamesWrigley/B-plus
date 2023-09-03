"
Some kind of view into a texture's data, which can be passed into a shader
    as a simple 64-bit integer handle, or one of the opaque sampler types.
Assumes the OpenGL extension `ARB_bindless_texture`.
This is much easier to manage than the old-school texture units and binding.
You can even pass an array of unrelated textures, as an array of uint64 (or uvec2)!

You should never create these yourself; they're generated by their owning Texture.

IMPORTANT: you must `view_activate()` an instance before it's used in a shader,
    and it should be `view_deactivate()`-d when not in use
    to free up GPU resources for other render passes.
Using an inactive handle leads to Undefined Behavior (a.k.a. wacky crashes).

The lifetime of this resource is managed by its owning Texture,
which is why this type does not inherit from `AbstractResource`.
"
mutable struct View
    handle::Ptr_View
    owner::AbstractResource # Can't type it as `Texture`, because that type doesn't exist yet

    is_active::Bool

    is_sampling::Bool # True if this is a 'Texture' view,
                      #   false if this is an 'Image' view.
end

"Tells the GPU to activate this handle so it can be used in a shader."
function view_activate(view::View)
    @bp_check(get_ogl_handle(view.owner) != Ptr_Texture(),
              "This view's owning texture has been destroyed")
    if !view.is_active
        view.is_active = true
        if view.is_sampling
            glMakeTextureHandleResidentARB(view.handle)
        else
            glMakeImageHandleResidentARB(view.handle, ImageAccessModes.read_write)
        end
    end
end

"Tells the GPU to deactivate this handle, potentially freeing up resources for other data to be loaded."
function view_deactivate(view::View)
    # Ideally we should check that the owning texture hasn't been destroyed, as with `view_activate()`,
    #    but in practice it's not as important and I feel that
    #    it will lead to a lot of initialization-order pain.
    if view.is_active
        view.is_active = false
        if view.is_sampling
            glMakeTextureHandleNonResidentARB(view.handle)
        else
            glMakeImageHandleNonResidentARB(view.handle)
        end
    end
end

# Unfortunately, OpenGL allows implementations to re-use the handles of destroyed views;
#    otherwise, I'd use that for hashing/equality.

export View, view_activate, view_deactivate


##################
##  Parameters  ##
##################

"
The parameters defining a 'simple' View.
Note that mip levels start at 1, not 0, to reflect Julia's 1-based indexing convention.
The 'layer' field allows you to pick a single layer of a 3D or cubemap texture,
    causing the view to act like a 2D texture.
"
Base.@kwdef struct SimpleViewParams
    mip_level::Int = 1
    layer::Optional{Int} = nothing
    access::E_ImageAccessModes = ImageAccessModes.read_write
end

"The parameters that uniquely define a texture's view."
const ViewParams = Union{Optional{TexSampler}, SimpleViewParams}

export SimpleViewParams, ViewParams


#####################
##   Constructors  ##
#####################

"
Creates a new sampled view from the given texture and optional sampler.
If no sampler is given, the texture's default sampler settings are used.

IMPORTANT: users shouldn't ever be creating these by hand;
    they should come from the Texture interfae.
"
function View(owner::AbstractResource, sampler::Optional{TexSampler})
    local handle::gl_type(Ptr_View)
    if exists(sampler)
        handle = glGetTextureSamplerHandleARB(get_ogl_handle(owner), get_sampler(sampler))
    else
        handle = glGetTextureHandleARB(get_ogl_handle(owner))
    end

    # Create the instance, and register it with the View-Debugger.
    instance = View(Ptr_View(handle), owner,
                    glIsTextureHandleResidentARB(handle),
                    true)
    service_ViewDebugging_add_view(instance.handle, instance)

    return instance
end

"
Creates a new simple view on a texture.
Note that mip levels start at 1, not 0, to reflect Julia's 1-based indexing convention.
The 'layer' parameter allows you to view a single layer of a 3D or cubemap texture,
    causing the view to act like a 2D texture.

IMPORTANT: users shouldn't ever be creating these by hand;
    they should come from the Texture interface.
"
function View(owner::AbstractResource, params::SimpleViewParams)
    handle::gl_type(Ptr_View) = glGetImageHandleARB(
        get_ogl_handle(owner),
        params.mip_level - 1,
        exists(params.layer),
        isnothing(params.layer) ? 0 : params.layer,
        GL_RGBA32F #NOTE: a hack left in place until we fix image views
    )

    # Create the instance, and register it with the View-Debugger.
    instance = View(Ptr_View(handle), owner,
                    glIsImageHandleResidentARB(handle),
                    false)
    service_ViewDebugging_add_view(instance.handle, instance)

    return instance
end