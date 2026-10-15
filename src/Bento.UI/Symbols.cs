using System.Windows.Shapes;

namespace Bento.UI;

// Original 24-unit symbols, independent of platform icon libraries.
internal static class Symbols
{
    public static StackPanel Caption(string text, string symbol)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        var icon = Create(symbol, 16); icon.Margin = new Thickness(0, 0, 8, 0); icon.IsHitTestVisible = false;
        var path = (System.Windows.Shapes.Path)((Canvas)((Viewbox)icon).Child).Children[0];
        path.SetBinding(Shape.StrokeProperty, new System.Windows.Data.Binding("Foreground")
        { RelativeSource = new System.Windows.Data.RelativeSource(System.Windows.Data.RelativeSourceMode.FindAncestor, typeof(Button), 1) });
        panel.Children.Add(icon); panel.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center });
        return panel;
    }
    public static FrameworkElement Create(string name, double size = 18)
    {
        string data = name switch
        {
            "Workspace" => "M4,3 L20,3 Q22,3 22,5 L22,19 Q22,21 20,21 L4,21 Q2,21 2,19 L2,5 Q2,3 4,3 M10,3 L10,21 M10,12 L22,12",
            "Gestures" => "M8,12 L8,5 Q8,2 10,2 Q12,2 12,5 L12,10 M12,8 Q16,7 16,11 M16,10 Q20,9 20,13 L20,16 Q20,22 14,22 L11,22 Q8,22 6,18 L3,13 Q2,11 4,10 Q6,9 8,12",
            "Updates" => "M5,8 A8,8 0 1 1 4,16 M5,3 L5,9 L11,9 M12,7 L12,13 L16,15",
            "Arrow" => "M5,12 L19,12 M13,6 L19,12 L13,18",
            "Space between windows" => "M2,4 L7,4 L7,20 L2,20 Z M17,4 L22,4 L22,20 L17,20 Z M10,12 L14,12 M11,10 L9,12 L11,14 M13,10 L15,12 L13,14",
            "Desktop margin" => "M2,7 L2,2 L7,2 M17,2 L22,2 L22,7 M22,17 L22,22 L17,22 M7,22 L2,22 L2,17 M7,7 L17,7 L17,17 L7,17 Z",
            "Background darkness" => "M4,3 L20,3 Q21,3 21,4 L21,20 Q21,21 20,21 L4,21 Q3,21 3,20 L3,4 Q3,3 4,3 M7,7 L17,7 L17,17 L7,17 Z M9,9 L9,15 M12,9 L12,15 M15,9 L15,15",
            "Appearance" => "M12,2 A10,10 0 1 1 12,22 A10,10 0 1 1 12,2 M12,2 L12,22 M15,5 L15,19 M18,8 L18,16",
            "Hold to split" => "M9,2 A7,7 0 1 1 9,16 A7,7 0 1 1 9,2 M9,5 L9,9 L12,11 M13,19 L22,19 M18,15 L18,23",
            "Smooth transitions" => "M2,17 C7,17 7,7 13,7 L21,7 M17,3 L21,7 L17,11 M3,21 L7,21 M2,12 L5,12",
            "Transition duration" => "M12,6 A8,8 0 1 1 12,22 A8,8 0 1 1 12,6 M12,10 L12,14 L16,14 M9,2 L15,2 M12,2 L12,6 M19,5 L21,7",
            "Let Bento handle edge snapping" => "M3,4 L21,4 L21,20 L3,20 Z M12,4 L12,20 M6,9 L9,12 L6,15 M18,9 L15,12 L18,15",
            "Arrange shortcut" => "M3,5 L21,5 Q23,5 23,7 L23,18 L1,18 L1,7 Q1,5 3,5 M5,9 L7,9 M11,9 L13,9 M17,9 L19,9 M5,13 L7,13 M10,14 L18,14",
            "GitHub repository" => "M6,3 A2,2 0 1 1 6,7 A2,2 0 1 1 6,3 M18,3 A2,2 0 1 1 18,7 A2,2 0 1 1 18,3 M6,17 A2,2 0 1 1 6,21 A2,2 0 1 1 6,17 M6,7 L6,17 M18,7 L18,9 Q18,13 14,13 L10,13 Q6,13 6,17",
            "Check when Bento starts" => "M12,2 L12,11 M7,5 A9,9 0 1 0 17,5 M8,15 L11,18 L17,12",
            "Save" => "M3,3 L18,3 L21,6 L21,21 L3,21 Z M7,3 L7,9 L17,9 L17,3 M7,21 L7,14 L17,14 L17,21",
            "Pause" => "M7,4 L7,20 M17,4 L17,20",
            "Resume" => "M6,3 L21,12 L6,21 Z",
            "Restore" => "M4,8 A9,9 0 1 1 4,17 M4,2 L4,9 L11,9",
            "Folder" => "M2,6 L9,6 L11,9 L22,9 L20,21 L2,21 Z M2,6 L2,3 L9,3 L11,6 L20,6 L20,9",
            "Download" => "M12,2 L12,16 M7,11 L12,16 L17,11 M3,17 L3,22 L21,22 L21,17",
            "Link" => "M10,7 L14,3 Q19,-1 23,4 Q25,7 21,11 L17,15 M7,9 L3,13 Q-1,17 3,21 Q7,25 11,21 L15,17 M8,16 L16,8",
            _ => "M3,4 L21,4 L21,20 L3,20 Z M12,4 L12,20"
        };
        var path = new System.Windows.Shapes.Path { Data = System.Windows.Media.Geometry.Parse(data), StrokeThickness = 1.6,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeLineJoin = PenLineJoin.Round };
        path.SetResourceReference(Shape.StrokeProperty, "Secondary");
        var canvas = new Canvas { Width = 24, Height = 24 }; canvas.Children.Add(path);
        return new Viewbox { Child = canvas, Width = size, Height = size };
    }
}
