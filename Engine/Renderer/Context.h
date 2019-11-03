#pragma once

#include "Helpers.h"


namespace Bplus::GL
{
    //Provides numerous helper functions and enums for managing OpenGL global state.
    //Ensures good performance by remembering the current state and ignoring duplicate calls.
    //Note that only one of these can exist in each thread,
    //    and this fact is enforced in the constructor.
    class BP_API Context
    {
    public:
        static const char* GLSLVersion() { return "#version 450"; }
        static uint8_t GLVersion_Major() { return 4; }
        static uint8_t GLVersion_Minor() { return 5; }

        //May be null if no context exists right now.
        //Note that each thread has its own singleton instance.
        static Context* GetCurrentContext();


        //Creates the context based on the given SDL window.
        //If there was an error, "errorMsg" will be set to it.
        Context(SDL_Window* owner, std::string& errorMsg);
        ~Context();

        //Gets whether this context got initialized properly.
        bool WasInitialized() const { return isInitialized; }
        //Gets the SDL window this context was created for.
        SDL_Window* GetOwner() const { return owner; }
        SDL_GLContext GetSDLContext() const { return sdlContext; }

        //Queries OpenGL for the current context state.
        //Call this after any OpenGL work is done not through this class.
        void RefreshDriverState();


        //Clears the current framebuffer's color and depth.
        void Clear(float r, float g, float b, float a, float depth);

        //Clears the current framebuffer's color.
        void Clear(float r, float g, float b, float a);
        //Clears the current framebuffer's depth.
        void Clear(float depth);
    
        template<typename TVec4>
        void Clear(const TVec4& rgba) { Clear(rgba.r, rgba.g, rgba.b, rgba.a); }

        void SetViewport(int minX, int minY, int width, int height);
        void SetViewport(int width, int height) { SetViewport(0, 0, width, height); }

        void SetScissor(int minX, int minY, int width, int height);
        void DisableScissor();

        bool SetVsyncMode(VsyncModes mode);
        VsyncModes GetVsyncMode() const { return currentVsync; }

        void SetFaceCulling(FaceCullModes mode);
        FaceCullModes GetFaceCulling() const { return currentCullMode; }

        void SetDepthTest(ValueTests mode);
        ValueTests GetDepthTest() const { return currentDepthTest; }

        void SetDepthWrites(bool canWriteToDepth);
        bool GetDepthWrites() const { return isDepthWriteEnabled; }

        void SetColorWriteMask(glm::bvec4 canWrite);
        glm::bvec4 GetColorWriteMask() const { return colorWriteMask; }

        #pragma region Blending

        //Gets the current global blend operation, assuming
        //    both color and alpha have the same setting.
        BlendStateRGBA GetBlending() const;
        //Sets both color and alpha blending to the given state.
        void SetBlending(const BlendStateRGBA& state);

        BlendStateRGB GetColorBlending() const { return currentColorBlending; }
        void SetColorBlending(const BlendStateRGB& state);

        BlendStateAlpha GetAlphaBlending() const { return currentAlphaBlending; }
        void SetAlphaBlending(const BlendStateAlpha& state);

        #pragma endregion

        #pragma region Stencil

        //Gets the current global stencil test, assuming
        //    both front- and back-faces have the same stencil test setting.
        const StencilTest& GetStencilTest() const;
        //Sets both front- and back-faces to use the given stencil test.
        void SetStencilTest(const StencilTest& test);

        const StencilTest& GetStencilTestFrontFaces() const { return stencilTestFront; }
        void SetStencilTestFrontFaces(const StencilTest& test);

        const StencilTest& GetStencilTestBackFaces() const { return stencilTestBack; }
        void SetStencilTestBackFaces(const StencilTest& test);


        //Gets the current global stencil write operations, assuming
        //    both front- and back-faces have the same stencil write settings.
        const StencilResult& GetStencilResult() const;
        //Sets both front- and back-faces to use the given stencil write operations.
        void SetStencilResult(const StencilResult& writeResults);

        const StencilResult& GetStencilResultFrontFaces() const { return stencilResultFront; }
        void SetStencilResultFrontFaces(const StencilResult& writeResult);

        const StencilResult& GetStencilResultBackFaces() const { return stencilResultBack; }
        void SetStencilResultBackFaces(const StencilResult& writeResult);


        //Gets the current global stencil mask, determining which bits
        //    can actually be written to by the "StencilResult" settings.
        GLuint GetStencilMask() const;
        void SetStencilMask(GLuint newMask);

        GLuint GetStencilMaskFrontFaces() const { return stencilMaskFront; }
        void SetStencilMaskFrontFaces(GLuint newMask);

        GLuint GetStencilMaskBackFaces() const { return stencilMaskBack; }
        void SetStencilMaskBackFaces(GLuint newMask);

        #pragma endregion



    private:

        bool isInitialized = false;
        SDL_GLContext sdlContext;
        SDL_Window* owner;

        bool isScissorEnabled, isDepthWriteEnabled;
        glm::bvec4 colorWriteMask;
        VsyncModes currentVsync;
        FaceCullModes currentCullMode;
        ValueTests currentDepthTest;
        BlendStateRGB currentColorBlending;
        BlendStateAlpha currentAlphaBlending;
        StencilTest stencilTestFront, stencilTestBack;
        StencilResult stencilResultFront, stencilResultBack;
        GLuint stencilMaskFront, stencilMaskBack;
        //TODO: Anything else to track?

        //TODO: Support MRT (many settings are per-RT).
    };
}