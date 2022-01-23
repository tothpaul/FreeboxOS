unit JournalAppels.Main;

{
   Journal d'appels pour la Freebox (c)2022 Execute SARL https://www.execute.fr

   cette application a été crée pour accéder facilement et rapidement à
   https://www.numeroinconnu.fr lors d'un appel sur la Freebox Revolution

   si un appel date de moins de 2s, le numéro est automatiquement envoyé
   sur le site en question.

   les boutons "btMarkRead" et "btClearHistory" sont invisibles et inutilisés
   (ils correspondent à l'interface Web de la freebox mais leur utilité me
   semble contestable).

   Par rapport à la Freebox, le nombre d'appel d'un numéro a été ajouté
   ainsi qu'une zone de recherche qui permet de filtrer les appels affichés.

   Une évolution possible serait d'implémenter le carnet d'adresse pour
   identifer certains appels (callEntty.name)

   Pour utiliser l'application vous devez disposez d'une Freebox.
   Elle a été testée sur une Freebox Revolution

   au premier lancement de l'application, celle-ci négocie un Token
   d'application qui est sauvegardé dans un fichier ini.

   Pour que l'application soit autorisée à accéder aux appels de la Freebox
   vous devez valider son accès directement sur le panneau de la Freebox.

   si votre afficheur n'est plus visible (comme le mien), il faut appuyer
   grosso modo à deux centimètres à droite du pied rouge 'Free by Starck"
   comprenant une prise USB.

   la flèche vers la droite valide l'accès de l'application

   +-------------------------------------------+
   |   Accès                                   |
   |   Oui|Non    <   >                        |
   |    +----+                                 |
   +---+     +---------------------------------+
       | [=] |               FreeBox Revolution
       +-----+

   Vous pouvez ensuite consulter (et révoquer au besoin) les droits sur
   l'interface Web de la Freebox
   => Paramètres de la Freebox / Divers / Gestion des accès
   => Onglet "Applications"

   Vous devez retrouver : Execute.JournalAppel (Nom Machine)
   cf APP_NAME
}

interface

uses
  Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, Vcl.StdCtrls,
  System.ImageList, System.SysUtils, System.Variants, System.IniFiles,
  System.StrUtils, System.DateUtils,
  Vcl.ImgList, Vcl.Controls, Vcl.ExtCtrls, System.Classes,
  Vcl.Graphics, Vcl.Forms, Vcl.Dialogs,
  Execute.FreeboxOS;

type
  TPaintBox = class(Vcl.ExtCtrls.TPaintBox)
  private
    MouseInside: Boolean;
    procedure CMMouseEnter(var Msg: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Msg: TMessage); message CM_MOUSELEAVE;
  end;

  TMain = class(TForm)
    pnTop: TPanel;
    pnBottom: TPanel;
    lbCalls: TListBox;
    btOK: TPaintBox;
    ImageList1: TImageList;
    btReload: TPaintBox;
    btMarkRead: TPaintBox;
    btClearHistory: TPaintBox;
    pnPending: TPanel;
    Label1: TLabel;
    ImageList2: TImageList;
    edSearch: TEdit;
    pbSearch: TPaintBox;
    TaskDialog1: TTaskDialog;
    lbNow: TLabel;
    procedure btOKPaint(Sender: TObject);
    procedure btOKClick(Sender: TObject);
    procedure btReloadPaint(Sender: TObject);
    procedure btMarkReadPaint(Sender: TObject);
    procedure btClearHistoryPaint(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btReloadClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure lbCallsDrawItem(Control: TWinControl; Index: Integer; Rect: TRect;
      State: TOwnerDrawState);
    procedure FormResize(Sender: TObject);
    procedure pbSearchPaint(Sender: TObject);
    procedure edSearchChange(Sender: TObject);
    procedure pbSearchClick(Sender: TObject);
    procedure lbCallsDblClick(Sender: TObject);
  private
    { Déclarations privées }
    ini: TIniFile;
    Freebox: TFreeboxOS;
    Calls: TCallEntries;
    filter: TList;
    procedure DrawButton(Button: TPaintBox; ImageIndex: Integer; Caption: string);
    procedure OnError(Sender: TObject; const Error, Description, Details: string);
    procedure OnVersion(Sender: TObject);
    procedure OnLoadAppToken(Sender: TObject; const uid: string; var AppToken: UTF8String);
    procedure OnSaveAppToken(Sender: TObject; const uid: string; const AppToken: UTF8String);
    procedure OnPending(Sender: TObject);
    procedure OnGranted(Sender: TObject);
    procedure OnCalls(Sender: TObject; const Calls: TCallEntries);
  public
    { Déclarations publiques }
  end;

var
  Main: TMain;

implementation

{$R *.dfm}

const
  APP_ID = 'Execute.FreeboxOS';
  APP_NAME = 'Execute.JournalAppel';
  APP_VERSION = '1.0';

{ TPaintBox }

procedure TPaintBox.CMMouseEnter(var Msg: TMessage);
begin
  MouseInside := True;
  Invalidate;
  Inherited;
end;

procedure TPaintBox.CMMouseLeave(var Msg: TMessage);
begin
  MouseInside := False;
  Invalidate;
  Inherited;
end;

{ TMain }

procedure TMain.btClearHistoryPaint(Sender: TObject);
begin
  DrawButton(btClearHistory, 2, 'Vider l''historique');
end;

procedure TMain.btMarkReadPaint(Sender: TObject);
begin
  DrawButton(btMarkRead, 1, 'Tout marquer comme lu');
end;

procedure TMain.btOKClick(Sender: TObject);
begin
  Application.Terminate;
end;

procedure TMain.btOKPaint(Sender: TObject);
begin
  var R: TRect := btOK.ClientRect;
  with btOK.Canvas do
  begin
    if btOK.MouseInside then
      Brush.Color := $eeeeee
    else
      Brush.Color := clWhite;
    Pen.Style := psClear;
    RoundRect(0, 0, R.Width, R.Height, 4, 4);

    ImageList1.Draw(btOK.Canvas, 11, R.Height div 2 - 8, 3);
    Inc(R.Left, 16);

    Font.Color := $825aff;
    var S: string := 'OK';
    TextRect(R, S, [tfSingleLine, tfVerticalCenter, tfCenter]);
  end;
end;

procedure TMain.btReloadClick(Sender: TObject);
begin
  Freebox.GetCalls();
end;

procedure TMain.btReloadPaint(Sender: TObject);
begin
  DrawButton(btReload, 0, 'Recharger');
end;

procedure TMain.DrawButton(Button: TPaintBox; ImageIndex: Integer;
  Caption: string);
begin
  var R: TRect := Button.ClientRect;
  with Button.Canvas do
  begin
    if Button.MouseInside then
    begin
      Brush.Color := $7348ff;
      Pen.Color := $7d55ff;
    end else begin
      Brush.Color := $6333ff;
      Pen.Style := psClear;
    end;
    RoundRect(0, 0, R.Width, R.Height, 4, 4);

    ImageList1.Draw(Button.Canvas, 11, R.Height div 2 - 8, ImageIndex);
    Inc(R.Left, 16);

    Font.Color := clWhite;
    Font.Size := 8;
    TextRect(R, Caption, [tfSingleLine, tfVerticalCenter, tfCenter]);
  end;
end;

procedure TMain.edSearchChange(Sender: TObject);
begin
  var Search := edSearch.Text;
  Filter.Clear;
  Filter.Capacity := Length(calls);
  if Search = '' then
  begin
    for var I := 0 to Length(Calls) - 1 do
      Filter.Add(@Calls[I]);
  end else begin
    for var I := 0 to Length(Calls) - 1 do
    begin
      if ContainsText(calls[I].name, Search)
      or ContainsText(calls[I].number, Search)
      or ContainsText(FormatDateTime('dd/mm/yyyy', calls[I].datetime), Search) then
        Filter.Add(@Calls[I]);
    end;
  end;
  lbCalls.Count := filter.Count;
end;

procedure TMain.FormCreate(Sender: TObject);
begin
  ini := TIniFile.Create(ChangeFileExt(Application.ExeName, '.ini'));
  filter := TList.Create;

  lbNow.Caption := 'mis à jour à ' + FormatDateTime('hh:nn', Now);

  Freebox := TFreeboxOS.Create(Self);

  // identification de l'application
  Freebox.AppId := APP_ID;
  Freebox.AppName := APP_NAME;
  Freebox.AppVersion := APP_VERSION;

  // gestion des réponses
  Freebox.OnError := OnError;
  Freebox.OnVersion := OnVersion;
  Freebox.OnLoadAppToken := OnLoadAppToken;
  Freebox.OnSaveAppToken := OnSaveAppToken;
  Freebox.OnPending := OnPending;
  Freebox.OnGranted := OnGranted;
  Freebox.OnCalls := OnCalls;

  // demander le journal d'appels
  Freebox.GetCalls();
end;

procedure TMain.FormDestroy(Sender: TObject);
begin
  filter.Free;
  ini.Free;
end;

procedure TMain.FormResize(Sender: TObject);
begin
  lbCalls.Invalidate;
end;

procedure TMain.lbCallsDblClick(Sender: TObject);
begin
  var Index := lbCalls.ItemIndex;
  if Index < 0 then
    Exit;
  var URL := 'https://www.numeroinconnu.fr/numero/' + PCallEntry(filter[Index]).number;
  ShellExecute(0, 'open', PChar(URL), nil, nil, SW_SHOW);
end;

procedure TMain.lbCallsDrawItem(Control: TWinControl; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
begin
  var Right := Rect.Right;
  var Top := Rect.Top;
  var Bottom := Rect.Bottom;
  var call: PCallEntry := filter[Index];
  with lbCalls.Canvas do
  begin
    if Odd(Index) then
    begin
      Brush.Color := $fafafa;
      Pen.Color := $ededed;
    end else begin
      Brush.Color := clWhite;
      Pen.Color := clWhite;
    end;
    Rectangle(Rect);
    ImageList2.Draw(lbCalls.Canvas, Rect.Left + 5, Rect.Top, Ord(call.&type));
    Inc(Rect.Left, 42);
    Rect.Width := 160;

    Font.Style := [fsBold];

    var N: string := call.name;
    var S: string := call.number;
    if (N <> '') and (N <> S) then
    begin
      Font.Color := clBlack;
      Rect.Height := Rect.Height div 2;
      TextRect(Rect, N, [tfSingleLine, tfVerticalCenter]);
      Rect.Top := Rect.Bottom;
      Rect.Bottom := Bottom;
    end;

    Font.Color := $8b1a55;
    TextRect(Rect, S, [tfSingleLine, tfVerticalCenter]);

    Rect.Top := Top;

    if call.count > 0 then
    begin
      S := (call.count + 1).ToString + ' appels';
      Font.Color := clBlack;
      Font.Style := [];
      Dec(Rect.Right, 15);
      TextRect(Rect, S, [tfSingleLine, tfVerticalCenter, tfRight]);
      Inc(Rect.Right, 15);
    end;

    Rect.Left := Rect.Right;
    Rect.Right := Right;
    Rect.Height := Rect.Height div 2;
    S := DateToString(call.datetime);
    Font.Color := clBlack;
    Font.Style := [];
    TextRect(Rect, S, [tfSingleLine, tfVerticalCenter]);
    Rect.Top := Rect.Bottom;
    Rect.Bottom := Bottom;
    S := 'Durée de l''appel : ' + Duration(call.duration);
    Font.Style := [fsItalic];
    Font.Color := $808080;
    TextRect(Rect, S, [tfSingleLine, tfVerticalCenter]);
  end;
end;

procedure TMain.OnError(Sender: TObject; const Error, Description, Details: string);
begin
  pnPending.Hide();
  TaskDialog1.Caption := 'Journal d''appels';
  TaskDialog1.Title := Error;
  TaskDialog1.Text := Description;
  TaskDialog1.ExpandedText := Details;
  TaskDialog1.Execute;
end;

procedure TMain.OnVersion(Sender: TObject);
begin
  Caption := 'Journal d''appels - ' + Freebox.Version.box_model_name;
end;

procedure TMain.OnLoadAppToken(Sender: TObject; const uid: string; var AppToken: UTF8String);
begin
  AppToken := ini.ReadString('Freebox', uid, '');
end;

procedure TMain.OnSaveAppToken(Sender: TObject; const uid: string; const AppToken: UTF8String);
begin
  ini.WriteString('Freebox', uid, AppToken);
end;

procedure TMain.OnPending(Sender: TObject);
begin
  pnPending.Show;
end;

procedure TMain.OnGranted(Sender: TObject);
begin
  pnPending.Hide;
end;

procedure TMain.OnCalls(Sender: TObject; const Calls: TCallEntries);
begin
  lbNow.Caption :=  'mis à jour à ' + FormatDateTime('hh:nn', Now);
  Self.Calls := Calls;
  // appel automatique de Numero Inconnu pour le dernier appel passé s'il a eut lieu il y a moins de 2 secondes
  if  (Length(Calls) > 0)
  and (Calls[0].name = Calls[0].number)
  and (SecondsBetween(Calls[0].datetime, Now) < 2) then
  begin
    var URL := 'https://www.numeroinconnu.fr/numero/' + Calls[0].number;
    ShellExecute(0, 'open', PChar(URL), nil, nil, SW_SHOW);
  end;
  edSearchChange(Self);
end;

procedure TMain.pbSearchClick(Sender: TObject);
begin
  edSearch.Text := '';
  edSearch.SetFocus;
end;

procedure TMain.pbSearchPaint(Sender: TObject);
begin
  ImageList1.Draw(pbSearch.Canvas, 15 - 8, 15 - 10, 4);
end;


end.
