using CsToml;

namespace TnmsResourcePrecacher;

[TomlSerializedObject]
internal sealed partial class PrecacheConfigDto
{
    [TomlValueOnSerialized(AliasName = "workshop_id")]
    public long? WorkshopId { get; set; }

    [TomlValueOnSerialized(AliasName = "resources")]
    public List<string>? Resources { get; set; }
}

public static class PrecacheConfig
{
    /// <summary>
    ///     Resources listed in global.toml, followed by the ones in every maps/*.toml that is for the current map. <br />
    ///     A map file with workshop_id is for the map of that workshop item, whatever the file is called. Without it,
    ///     the file is for the map it is named after. <br />
    ///     Files are read on every call so that edits apply on the next map load. <br />
    ///     A file that fails to load is reported through <paramref name="onError" /> and skipped, so that it does not
    ///     take the other files' resources with it.
    /// </summary>
    public static List<string> LoadResources(string baseDirectoryPath, string mapName, IReadOnlySet<long> workshopIds,
        Action<string, Exception> onError)
    {
        var resources = new List<string>();

        if (ReadConfig(Path.Combine(baseDirectoryPath, "global.toml"), onError) is { } global)
            AppendResources(resources, global);

        var mapsDirectoryPath = Path.Combine(baseDirectoryPath, "maps");
        if (!Directory.Exists(mapsDirectoryPath))
            return resources;

        foreach (var configFilePath in Directory.GetFiles(mapsDirectoryPath, "*.toml").Order(StringComparer.OrdinalIgnoreCase))
        {
            if (ReadConfig(configFilePath, onError) is not { } config)
                continue;

            var isCurrentMap = config.WorkshopId is { } workshopId
                ? workshopIds.Contains(workshopId)
                : Path.GetFileNameWithoutExtension(configFilePath).Equals(mapName, StringComparison.OrdinalIgnoreCase);

            if (isCurrentMap)
                AppendResources(resources, config);
        }

        return resources;
    }

    private static PrecacheConfigDto? ReadConfig(string configFilePath, Action<string, Exception> onError)
    {
        if (!File.Exists(configFilePath))
            return null;

        try
        {
            return CsTomlSerializer.Deserialize<PrecacheConfigDto>(File.ReadAllBytes(configFilePath));
        }
        catch (Exception e)
        {
            onError(configFilePath, e);
            return null;
        }
    }

    private static void AppendResources(List<string> resources, PrecacheConfigDto config)
    {
        if (config.Resources == null)
            return;

        foreach (var resource in config.Resources)
        {
            if (!string.IsNullOrWhiteSpace(resource) && !resources.Contains(resource, StringComparer.OrdinalIgnoreCase))
                resources.Add(resource);
        }
    }
}
