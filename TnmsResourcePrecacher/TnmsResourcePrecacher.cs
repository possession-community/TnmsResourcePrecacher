using CsToml.Error;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Sharp.Shared;
using Sharp.Shared.Listeners;
using TnmsPluginFoundation;

namespace TnmsResourcePrecacher;

public sealed class TnmsResourcePrecacher(
    ISharedSystem sharedSystem,
    string dllPath,
    string sharpPath,
    Version? version,
    IConfiguration coreConfiguration,
    bool hotReload)
    : TnmsPlugin(sharedSystem, dllPath, sharpPath, version, coreConfiguration, hotReload), IGameListener
{
    public int ListenerVersion => 1;
    public int ListenerPriority => 0;
    public override string DisplayName => "TnmsResourcePrecacher";
    public override string DisplayAuthor => "faketuna";
    public override string BaseCfgDirectoryPath => Path.Combine(ModuleDirectory);
    public override string ConVarConfigPath => "";
    public override string PluginPrefix => "[PRECACHE]";
    public override bool UseTranslationKeyInPluginPrefix => false;

    private List<string> _resources = [];

    protected override void TnmsOnPluginLoad(bool hotReload)
    {
        SharedSystem.GetModSharp().InstallGameListener(this);
        Logger.LogInformation("TnmsResourcePrecacher initialized.");
    }

    protected override void TnmsOnPluginUnload(bool hotReload)
    {
        SharedSystem.GetModSharp().RemoveGameListener(this);
        Logger.LogInformation("TnmsResourcePrecacher shutdown.");
    }

    // The map is resolved here because only PrecacheResource is allowed in OnResourcePrecache.
    public void OnServerInit()
    {
        var modSharp = SharedSystem.GetModSharp();
        var mapName = modSharp.GetMapName() ?? string.Empty;

        // GetAddonName is no use here: the engine fills it in SpawnServer, which runs after OnResourcePrecache.
        // The workshop manager already knows the map by now, but only by name, so two workshop items that ship a
        // map of the same name both count as the current one.
        var workshopIds = new HashSet<long>();
        foreach (var (publishFileId, name) in modSharp.ListWorkshopMaps())
        {
            if (name.Equals(mapName, StringComparison.OrdinalIgnoreCase))
                workshopIds.Add((long)publishFileId);
        }

        Logger.LogInformation("Map {MapName}, workshop ids [{WorkshopIds}]", mapName, string.Join(", ", workshopIds));

        _resources = PrecacheConfig.LoadResources(ModuleDirectory, mapName, workshopIds, OnConfigError);
    }

    private void OnConfigError(string configFilePath, Exception exception)
    {
        if (exception is not CsTomlSerializeException e)
        {
            Logger.LogError(exception, "Failed to load precache config {Path}", configFilePath);
            return;
        }

        // Message carries a stack trace: the line number and the inner message are the readable part.
        // There are no parse errors when the file is valid TOML but a value has the wrong type.
        var errors = e.ParseExceptions is { Count: > 0 } parseErrors
            ? string.Join("; ", parseErrors.Select(p => $"line {p.LineNumber}: {p.InnerException?.Message ?? p.Message}"))
            : e.InnerException?.Message ?? e.Message;
        Logger.LogError("Failed to parse precache config {Path}: {Errors}", configFilePath, errors);
    }

    public void OnResourcePrecache()
    {
        foreach (var resource in _resources)
        {
            SharedSystem.GetModSharp().PrecacheResource(resource);
            Logger.LogInformation("Precached resource: {Path}", resource);
        }
    }
}
