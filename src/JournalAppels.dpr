program JournalAppels;

uses
  Vcl.Forms,
  JournalAppels.Main in 'JournalAppels.Main.pas' {Main},
  Execute.RTTI in '..\lib\Execute.RTTI.pas',
  Execute.UTF8.Utils in '..\lib\Execute.UTF8.Utils.pas',
  Execute.JSON.UTF8 in '..\lib\Execute.JSON.UTF8.pas',
  Execute.SHA1 in '..\lib\Execute.SHA1.pas',
  Execute.FreeboxOS in '..\lib\Execute.FreeboxOS.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMain, Main);
  Application.Run;
end.
