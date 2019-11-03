#include "../Engine/App.h"

//A template command-line + window app based on B+ and SDL.
//Command-line arguments:
//    -noWriteConfig to not update the config file on exit
//          (used automatically when running from the IDE in Release mode).

namespace
{
    std::unique_ptr<Bplus::ConfigFile> Config;
    std::unique_ptr<Bplus::App> App;
    int exitCode = 0;


    void OnError(const std::string& msg)
    {
        exitCode = 1;
        std::cout << "Error: " << msg << "\n\n";
        if (App != nullptr)
        {
            SDL_ShowSimpleMessageBox(SDL_MessageBoxFlags::SDL_MESSAGEBOX_ERROR,
                                     "Error", msg.c_str(),
                                     nullptr);
            App->Quit(true);
        }
    }
}


class MyConfigFile : public Bplus::ConfigFile
{
public:

    MyConfigFile(const fs::path& filePath, bool disableWrite)
        : Bplus::ConfigFile(filePath, ::OnError, disableWrite)
    {

    }

    virtual void ResetToDefaults() override
    {
        Bplus::ConfigFile::ResetToDefaults();
    }

protected:

    virtual void _FromToml(const toml::Value& document) override
    {

    }
    virtual void _ToToml(toml::Value& document) const override
    {

    }
};


class MyApp : public Bplus::App
{
public:

    MyApp(bool noConfigWriteOnExit)
        : Bplus::App(*::Config, ::OnError)
    {

    }

protected:

    virtual void ConfigureMainWindow(int& flags, std::string& title)
    {
        App::ConfigureMainWindow(flags, title);
        title = "My B+ App";
    }
    virtual void ConfigureOpenGL(bool& doubleBuffering,
                                 int& depthBits, int& stencilBits,
                                 Bplus::GL::VsyncModes& vSyncMode)
    {
        App::ConfigureOpenGL(doubleBuffering, depthBits, stencilBits, vSyncMode);
    }

    virtual void OnRendering(float deltaT)
    {
        GetContext().Clear(1, 1, 1, 1,
                           1);

        auto doMask = [](GLuint originalMask)
        {
            glStencilMask(originalMask);
            GLint newMaskI;
            glGetIntegerv(GL_STENCIL_WRITEMASK, &newMaskI);
            GLuint newMask_Reinterpret = *((GLuint*)(&newMaskI)),
                   newMask_Cast = (GLuint)newMaskI;

            std::string data = "From ";
            data += std::to_string(originalMask);
            data += " to [reinterpret:";
            data += std::to_string(newMask_Reinterpret);
            data += "] [cast:";
            data += std::to_string(newMask_Cast);
            data += "]";
            ImGui::Text(data.c_str());
        };
        doMask(25);
        doMask(~(0U));
        doMask(~(0U) - 32 - 8 - 256);
        doMask(~(0U) - 1 - 32 - 8 - 256);
        doMask(-1);
    }
};



int main(int argc, char* argv[])
{
    //Parse command-line arguments.
    bool noWriteConfig = false;
    for (int i = 0; i < argc; ++i)
    {
        auto lowercase = std::string(argv[i]);
        for (auto& c : lowercase)
            if (std::isupper(c))
                c = std::tolower(c);

        if (lowercase == std::string("-nowriteconfig"))
            noWriteConfig = true;
    }

    //Load the config file.
    Config = std::make_unique<MyConfigFile>(fs::current_path() / "Config.toml",
                                            noWriteConfig);

    //Run the app.
    App = std::make_unique<MyApp>(noWriteConfig);
    App->Run();

    return exitCode;
}