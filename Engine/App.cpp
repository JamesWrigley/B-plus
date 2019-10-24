#include "App.h"

#include <chrono>
#include <thread>

using namespace Bplus;


ConfigFile::ConfigFile(const fs::path& tomlFile,
                       ErrorCallback onError, bool disableWrite)
    : FilePath(tomlFile), DisableWrite(disableWrite),
      OnError(onError)
{
}

void ConfigFile::LoadFromFile()
{
    auto tryParse = toml::parseFile(FilePath.string());
    if (!tryParse.valid())
    {
        OnError(std::string() + "Error reading/parsing TOML config file: " +
                    tryParse.errorReason);
        return;
    }

    auto tomlDoc = tryParse.value;

    try
    {
        FromToml(tomlDoc);
    }
    catch (...)
    {
        OnError("Unknown error loading TOML config file");
    }
}
void ConfigFile::WriteToFile() const
{
    if (DisableWrite)
        return;

    try
    {
        toml::Value doc;
        ToToml(doc);

        std::ofstream fileStream(FilePath, std::ios::trunc);
        if (fileStream.is_open())
            doc.writeFormatted(&fileStream, toml::FORMAT_INDENT);
        else
            OnError(std::string("Error opening config file to write: ") + FilePath.string());
    }
    catch (...)
    {
        OnError("Error writing updated config file");
    }
}

void ConfigFile::FromToml(const toml::Value& document)
{
    IsWindowMaximized = IO::TomlTryGet(document, "IsWindowMaximized", false);

    const auto* found = document.find("LastWindowSize");
    if (found != nullptr)
    {
        LastWindowSize.x = (glm::u32)found->get<int64_t>(0);
        LastWindowSize.y = (glm::u32)found->get<int64_t>(1);
    }

    this->_FromToml(document);
    this->OnDeserialized();
}
void ConfigFile::ToToml(toml::Value& document) const
{
    document["IsWindowMaximized"] = IsWindowMaximized;
    
    auto windowSize = toml::Array();
    windowSize.push_back((int64_t)LastWindowSize.x);
    windowSize.push_back((int64_t)LastWindowSize.y);
    document["LastWindowSize"] = std::move(windowSize);
}



App::App(std::unique_ptr<ConfigFile>&& config, ErrorCallback onError)
    : MainWindow(nullptr), OpenGLContext(nullptr), ImGuiContext(nullptr),
      WorkingPath(config->FilePath.parent_path()),
      ContentPath(WorkingPath / "content"),
      Config(std::move(config)), OnError(onError)
{
    isRunning = false;
    Config->OnError = OnError;
}
App::~App()
{
    if (isRunning)
    {
        //Force-quit, and be careful that an exception isn't thrown.
        try { Quit(true); }
        catch (...) {}
    }
}

void App::Run()
{
    timeSinceLastPhysicsUpdate = 0;
    lastFrameStartTime = SDL_GetPerformanceCounter();
    isRunning = true;

    Config->LoadFromFile();

    #pragma region Initialization

    //Set up SDL.
    if (!TrySDL(SDL_Init(SDL_INIT_VIDEO), "Couldn't initialize SDL"))
        return;

    //Set up the window.
    int windowFlags;
    std::string windowTitle;
    ConfigureMainWindow(windowFlags, windowTitle);
    MainWindow = SDL_CreateWindow(windowTitle.c_str(),
                                  SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                  (int)Config->LastWindowSize.x,
                                  (int)Config->LastWindowSize.y,
                                  windowFlags);
    if (!TrySDL(MainWindow, "Error creating main window"))
        return;

    //Initialize OpenGL.
    bool doubleBuffer;
    int depthBits, stencilBits;
    GL::VsyncModes vSyncMode;
    ConfigureOpenGL(doubleBuffer, depthBits, stencilBits, vSyncMode);
    if (!TrySDL(SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, GLVersion_Major()), "Error setting GL major version") ||
        !TrySDL(SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, GLVersion_Minor()), "Error setting GL minor version") ||
        !TrySDL(SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE), "Error setting context profile") ||
        !TrySDL(SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, doubleBuffer ? 1 : 0), "Error setting double-buffering") ||
        !TrySDL(SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, depthBits), "Error setting back buffer's depth bits") ||
        !TrySDL(SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, stencilBits), "Error setting back buffer's stencil bits") ||
        !TrySDL(OpenGLContext = SDL_GL_CreateContext(MainWindow), "Error initializing OpenGL context")
      )
    {
        return;
    }

    //Set up V-Sync.
    int vSyncResult = SDL_GL_SetSwapInterval((int)vSyncMode);
    if (vSyncResult != 0 && vSyncMode == GL::VsyncModes::Adaptive)
        vSyncResult = SDL_GL_SetSwapInterval((int)GL::VsyncModes::On);
    if (!TrySDL(vSyncResult, "Error setting vsync setting"))
        return;

    //Initialize GLEW.
    glewExperimental = GL_TRUE;
    auto glewError = glewInit();
    if (glewError != GLEW_OK)
    {
        OnError(std::string("Error setting up GLEW: ") +
                    (const char*)glewGetErrorString(glewError));
        return;
    }

    //Initialize Dear ImGUI.
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiContext = &ImGui::GetIO();
    ImGuiContext->ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    ImGui::StyleColorsDark(); //Default to dark theme, for sanity
    ImGui_ImplSDL2_InitForOpenGL(MainWindow, OpenGLContext);
    ImGui_ImplOpenGL3_Init(GLSLVersion());

    //Allow child class initialization.
    OnBegin();

    #pragma endregion

    //Now, run the main loop.
    while (isRunning)
    {
        //Process window/OS events.
        SDL_Event sdlEvent;
        while (SDL_PollEvent(&sdlEvent) != 0)
        {
            //Update ImGui.
            ImGui_ImplSDL2_ProcessEvent(&sdlEvent);
            
            //Update this app's base functionality.
            switch (sdlEvent.type)
            {
                case SDL_EventType::SDL_QUIT:
                    OnQuit(false);
                break;

                case SDL_EventType::SDL_WINDOWEVENT:
                    switch (sdlEvent.window.event)
                    {
                        case SDL_WINDOWEVENT_CLOSE:
                            OnQuit(false);
                        break;

                        case SDL_WINDOWEVENT_RESIZED:
                            if (sdlEvent.window.data1 < (Sint32)MinWindowSize.x ||
                                sdlEvent.window.data2 < (Sint32)MinWindowSize.y)
                            {
                                SDL_SetWindowSize(
                                    MainWindow,
                                    std::max(sdlEvent.window.data1, (int)MinWindowSize.x),
                                    std::max(sdlEvent.window.data2, (int)MinWindowSize.y));
                            }
                        break;

                        default: break;
                    }
                break;

                default: break;
            }

            //Update the config.
            Config->IsWindowMaximized = (SDL_GetWindowFlags(MainWindow) &
                                             SDL_WINDOW_MAXIMIZED) != 0;
            if (!Config->IsWindowMaximized)
            {
                int wndW, wndH;
                SDL_GetWindowSize(MainWindow, &wndW, &wndH);
                Config->LastWindowSize.x = (glm::u32)wndW;
                Config->LastWindowSize.y = (glm::u32)wndH;
            }

            //Update the child class.
            OnEvent(sdlEvent);
        }

        //Now run an update frame of the App.
        uint64_t newFrameTime = SDL_GetPerformanceCounter();
        double deltaT = (newFrameTime - lastFrameStartTime) /
            (double)SDL_GetPerformanceFrequency();

        //If the frame-rate is too fast, wait.
        if (deltaT < MinDeltaT)
        {
            double missingTime = MinDeltaT - deltaT;
            std::this_thread::sleep_for(std::chrono::duration<double>(missingTime + .00000001));
            continue;
            return;
        }
        lastFrameStartTime = newFrameTime;

        //Initialize the GUI frame.
        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplSDL2_NewFrame(MainWindow);
        ImGui::NewFrame();

        //Update physics.
        timeSinceLastPhysicsUpdate += deltaT;
        while (timeSinceLastPhysicsUpdate > PhysicsTimeStep)
        {
            timeSinceLastPhysicsUpdate -= PhysicsTimeStep;
            OnPhysics(PhysicsTimeStep);
        }

        //Update other stuff.
        OnUpdate((float)deltaT);

        //Do rendering.
        GL::SetViewport((int)ImGuiContext->DisplaySize.x,
                        (int)ImGuiContext->DisplaySize.y);
        OnRendering((float)deltaT);

        //Finally, do GUI rendering.
        ImGui::Render();
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
        SDL_GL_SwapWindow(MainWindow);
    }
}
void App::OnQuit(bool force)
{
    //Clean up OpenGL.
    if (OpenGLContext != nullptr)
        SDL_GL_DeleteContext(OpenGLContext);
    OpenGLContext = nullptr;

    //Clean up the SDL window.
    if (MainWindow != nullptr)
        SDL_DestroyWindow(MainWindow);
    MainWindow = nullptr;

    //Clean up SDL itself.
    if ((SDL_WasInit(SDL_INIT_EVERYTHING) & SDL_INIT_EVENTS) != 0)
        SDL_Quit();

    Config->WriteToFile();
    isRunning = true;
}

bool App::TrySDL(int returnCode, const std::string& msgPrefix)
{
    if (returnCode != 0)
        OnError(msgPrefix + ": " + SDL_GetError());

    return returnCode == 0;
}
bool App::TrySDL(void* shouldntBeNull, const std::string& msgPrefix)
{
    if (shouldntBeNull == nullptr)
        return TrySDL(-1, msgPrefix);
    else
        return true;
}