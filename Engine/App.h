#pragma once

#include "IO.h"
#include "RenderLibs.h"


namespace Bplus
{
    //A base-class for config data associated with an App.
    //Loaded in from a specific file alongside the app,
    //    and written back to the file (creating if it doesn't exist yet)
    //    on close.
    //Supports TOML deserialization; all you have to do
    //    is implement the two relevant virtual methods.
    class BP_API ConfigFile
    {
    public:
        ErrorCallback OnError;

        bool IsWindowMaximized;
        glm::uvec2 LastWindowSize;

        const fs::path FilePath;
        const bool DisableWrite; //Useful when running in the IDE.


        ConfigFile(const fs::path& tomlFilePath,
                   ErrorCallback onError, bool disableWrite);
        virtual ~ConfigFile() { }

        void FromToml(const toml::Value& document);
        void LoadFromFile();

        void ToToml(toml::Value& document) const;
        void WriteToFile() const;


    protected:
        virtual void _FromToml(const toml::Value& document) { }
        virtual void _ToToml(toml::Value& document) const { }

        //Called after this config file is loaded from a TOML file.
        //Use this to post-proceses any config data (e.x. to find errors).
        virtual void OnDeserialized() { }
    };


    //An abstract base class for an SDL app using this renderer.
    //Handles all the setup/shutdown for SDL, the "main" window, and ImGUI.
    class BP_API App
    {
    public:

        static const char* GLSLVersion() { return "400"; }
        static uint8_t GLVersion_Major() { return 4; }
        static uint8_t GLVersion_Minor() { return 0; }


        SDL_Window* MainWindow;
        SDL_GLContext OpenGLContext;
        ImGuiIO* ImGuiContext;

        std::unique_ptr<ConfigFile> Config;
        ErrorCallback OnError;

        const fs::path WorkingPath, ContentPath;


        //The main window will never be allowed to get smaller than this.
        glm::u32vec2 MinWindowSize{ 250, 250 };

        //The length of each physics time-step.
        //Physics is updated in time-steps of the exact same size each frame,
        //    for more stable and predictable behavior.
        //If the frame-rate is low, multiple physics updates will happen each frame
        //    so the system can keep up.
        float PhysicsTimeStep = 1.0f / 50.0f;
        //The max number of physics updates that can happen per frame.
        //    if more than this are needed in one frame,
        //    physics will appear to run in slow motion.
        //This setting is important because without it,
        //    the number of physics steps per frame could escalate endlessly.
        uint_fast32_t MaxPhysicsStepsPerFrame = 10;

        //A minimum cap on frame time.
        //If the frame is faster than this, the program will sleep for a bit.
        //A zero or negative value means "no cap".
        float MinDeltaT = -1;


        App(std::unique_ptr<ConfigFile>&& config, ErrorCallback onError);
        virtual ~App();

        //Disable move/copy constructors.
        App(const App& cpy) = delete;
        App& operator=(const App& cpy) = delete;

        //Runs this app from beginning to end, blocking the calling thread
        //    until it's completed.
        void Run();

        //Asks this app to quit running. If "force" is false,
        //    the app has the choice of ignoring/postponing it.
        void Quit(bool force) { if (isRunning) OnQuit(force); }
        //Gets whether the app has already successfully quit.
        bool DidQuit() const { return !isRunning; }


    protected:

        //Called as the app starts running.
        //Override this to set the main window's properties.
        //Default behavior:
        //  * Sets "flags" to SDL_WINDOW_SHOWN, SDL_WINDOW_OPENGL, SDL_WINDOW_RESIZABLE,
        //      and (based on config) SDL_WINDOW_MAXIMIZED.
        //  * Sets "title" to "B+ App".
        virtual void ConfigureMainWindow(int& flags, std::string& title)
        {
            flags = SDL_WINDOW_SHOWN | SDL_WINDOW_OPENGL | SDL_WINDOW_RESIZABLE |
                        (Config->IsWindowMaximized ? SDL_WINDOW_MAXIMIZED : 0);
            title = "B+ App";
        }
        //Called as the app starts running.
        //Override this to set the OpenGL context's properties.
        //Note that each of these correspond to a "SDL_GL_SetAttribute()" call.
        //Default behavior:
        //  * double-buffering is turned on.
        //  * 24-bit depth, and 8-bit stencil
        //  * v-sync is set to "adaptive" (which, if not available,
        //      will automatically fall back to normal vsync).
        virtual void ConfigureOpenGL(bool& doubleBuffering,
                                     int& depthBits, int& stencilBits,
                                     GL::VsyncModes& vSyncMode)
        {
            doubleBuffering = true;
            depthBits = 24;
            stencilBits = 8;
            vSyncMode = GL::VsyncModes::Adaptive;
        }

        //Called after the app has just started running.
        virtual void OnBegin() { }

        //Called when quitting the app.
        //If "force" is false, you are allowed to omit the base class call
        //    "App::OnQuit(force)" to cancel the quit.
        //Default behavior: cleans up all resources and sets "isRunning" to false.
        virtual void OnQuit(bool force);

        //Processes an OS/window event on the main window.
        virtual void OnEvent(const SDL_Event& osEvent) { }
        //Does physics updates.
        virtual void OnPhysics(float deltaT) { }
        //Does normal (i.e. non-physics) updates.
        virtual void OnUpdate(float deltaT) { }
        //Does all the rendering. Called immediately after "DoUpdate()".
        virtual void OnRendering(float deltaT) { GL::Clear(1, 0, 1, 1, 1); }


        //Given an SDL return code, responds accordingly if it represents an error.
        bool TrySDL(int returnCode, const std::string& msgPrefix);
        //Given an SDL return asset, responds accordingly if it's null.
        bool TrySDL(void* shouldntBeNull, const std::string& msgPrefix);


    private:

        double timeSinceLastPhysicsUpdate;
        uint64_t lastFrameStartTime;
        bool isRunning;
    };
}