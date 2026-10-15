using System.Windows.Shapes;

namespace Bento.UI;

// Original 24-unit symbols, independent of platform icon libraries.
internal static class Symbols
{
    public static FrameworkElement Create(string name, double size = 18)
    {
        string data = name switch
        {
            "Workspace" => "M4,3 L20,3 Q22,3 22,5 L22,19 Q22,21 20,21 L4,21 Q2,21 2,19 L2,5 Q2,3 4,3 M10,3 L10,21 M10,12 L22,12",
            "Gestures" => "M8,12 L8,5 Q8,2 10,2 Q12,2 12,5 L12,10 M12,8 Q16,7 16,11 M16,10 Q20,9 20,13 L20,16 Q20,22 14,22 L11,22 Q8,22 6,18 L3,13 Q2,11 4,10 Q6,9 8,12",
            "Updates" => "M5,8 A8,8 0 1 1 4,16 M5,3 L5,9 L11,9 M12,7 L12,13 L16,15",
            "Arrow" => "M5,12 L19,12 M13,6 L19,12 L13,18",
            _ => "M3,4 L21,4 L21,20 L3,20 Z M12,4 L12,20"
        };
        var path = new System.Windows.Shapes.Path { Data = System.Windows.Media.Geometry.Parse(data), StrokeThickness = 1.6,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round };
        path.SetResourceReference(Shape.StrokeProperty, "Secondary");
        var canvas = new Canvas { Width = 24, Height = 24 }; canvas.Children.Add(path);
        return new Viewbox { Child = canvas, Width = size, Height = size };
    }
}
