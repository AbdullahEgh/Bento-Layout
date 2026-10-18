namespace Bento.Tests;

// Pure geometry tests can run on any .NET 10 host, without WPF or a desktop.
internal static class Program
{
    private static int passed, failed;
    private static int Main()
    {
        ParityGeometryTests.RunAll();
        Console.WriteLine($"RESULT: {passed} passed, {failed} failed");
        return failed == 0 ? 0 : 1;
    }
    public static void Run(string name, Action test)
    {
        try { test(); passed++; Console.WriteLine($"PASS {name}"); }
        catch (Exception ex) { failed++; Console.Error.WriteLine($"FAIL {name}: {ex.Message}"); }
    }
    public static void Check(bool value) { if (!value) throw new Exception("Assertion failed."); }
    public static void Equal<T>(T expected, T actual) { if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"Expected {expected}; got {actual}."); }
}
