unit Execute.FreeboxOS;

{
   FreeboxOS Component for Delphi (c)2022 Execute SARL https://www.execute.fr

   free to use for GPL products

   contact me for any commercial usage <contact@execute.fr>
}

{$IFDEF DEBUG}
{.$DEFINE FREEBOX_LOG}
{$ENDIF}
interface

// https://dev.freebox.fr/sdk/os/

uses
  Winapi.Windows,
  Winapi.Winsock,
  Vcl.Dialogs,
  System.Classes,
  System.SysUtils,
  System.Net.HttpClient,
  System.DateUtils,
  Execute.JSON.UTF8,
  Execute.SHA1;

type
  TErrorEvent = procedure(Sender: TObject; const Error, Description, Details: string) of object;

  TLoadAppTokenEvent = procedure(Sender: TObject; const uuid: string; var AppToken: UTF8String) of object;
  TSaveAppTokenEvent = procedure(Sender: TObject; const uuid: string; const AppToken: UTF8String) of object;

  TCallEntry = record
    id        : Integer;
    &type     : (missed, accepted, outgoing);
    datetime  : TDateTime;
    number    : string;  // UTF8String;
    name      : string;  // UTF8String;
    duration  : Integer; // seconds
    &new      : Boolean;
    contact_id: Integer;
  // computed fields
    count     : Integer;
  end;
  PCallEntry = ^TCallEntry;
  TCallEntries = TArray<TCallEntry>;

  TCallsEvent = procedure(Sender: TObject; const Calls: TCallEntries) of object;

(*
{
  "box_model_name":"Freebox Server (r1)",
  "api_base_url":"\/api\/",
  "https_port":50135,
  "device_name":"Freebox Server",
  "https_available":true,
  "box_model":"fbxgw-r1\/full",
  "api_domain":"g1zc7v0y.fbxos.fr",
  "uid":"565fc...7c37",
  "api_version":"8.5",
  "device_type":"FreeboxServer1,1"
}
*)
  TFreeboxVersion = record
    box_model_name: UTF8String;
    api_base_url: UTF8String;
    https_port: Word;
    device_name: UTF8String;
    https_available: Boolean;
    box_model: UTF8String;
    api_domain: UTF8String;
    uid: UTF8String;
    api_version: UTF8String;
    device_type: UTF8String;
  end;

  TFreeboxOS = class(TComponent)
  private
  // Application identification
    FAppId: string;
    FAppName: string;
    FAppVersion: string;
  // Version
    FVersion: TFreeboxVersion;
  // Freebox URL
    FURL: string;
  // Delivred token for this app
    FAppToken: UTF8String;
  // Delivred session token
    FSessionToken: UTF8String;
  // Events
    FOnError: TErrorEvent;
    FOnVersion: TNotifyEvent;
    FOnPending: TNotifyEvent;
    FOnGranted: TNotifyEvent;
    FOnLoadAppToken: TLoadAppTokenEvent;
    FOnSaveAppToken: TSaveAppTokenEvent;
    FOnCalls: TCallsEvent;
    procedure SetURL(const AURL: string);
  public
    procedure GetCalls(ASync: Boolean = True);
    property Version: TFreeboxVersion read FVersion;
  published
    // user defined properties
    property AppId: string read FAppId write FAppId;
    property AppName: string read FAppName write FAppName;
    property AppVersion: string read FAppVersion write FAppVersion;
    // something wrong occurs
    property OnError: TErrorEvent read FOnError write FOnError;
    // fired when the a Freebox is discovered, you can use Version.uuid to setup the AppToken member
    property OnVersion: TNotifyEvent read FOnVersion write FOnVersion;
    // Load/Save AppToken
    property OnLoadAppToken: TLoadAppTokenEvent read FOnLoadAppToken write FOnLoadAppToken;
    property OnSaveAppToken: TSaveAppTokenEvent read FOnSaveAppToken write FOnSaveAppToken;
    // fired when the Freebox authorization is requested
    property OnPending: TNotifyEvent read FOnPending write FOnPending;
    // fired when the application is allowed by the Freebox
    property OnGranted: TNotifyEvent read FOnGranted write FOnGranted;
    // the Calls log is available, you should take a copy of the parameter
    property OnCalls: TCallsEvent read FOnCalls write FOnCalls;
  end;

function DateToString(const Date: TDateTime): string;
function Duration(Seconds: Integer): string;

implementation

function DateToString(const Date: TDateTime): string;
begin
  var diff := DaysBetween(DateOf(Date), DateOf(Now));
  //if SameDate(Now, Date) then
  if diff = 0 then
  begin
    Result := 'aujourd''hui à ' + FormatDateTime('hh:nn:ss', Date);
    Exit;
  end;
  //if SameDate(Yesterday, Date) then
  if diff = 1 then
  begin
    Result := 'hier à ' + FormatDateTime('hh:nn:ss', Date);
    Exit;
  end;
  if diff < 3 then
    Result := 'Il y a ' + diff.ToString + ' jours à ' + FormatDateTime('hh:nn:ss', Date)
  else
  if diff < 30 then
    Result := FormatDateTime('dddd dd mmm à hh:nn:ss', Date)
  else
    Result := 'Le ' + FormatDateTime('dd/mm/yyyy à hh:nn:ss', Date);
end;

function Duration(Seconds: Integer): string;
begin
  Result := '';
  if Seconds >= 60 then
  begin
    var Minutes := Seconds div 60;
    Dec(Seconds, 60 * Minutes);
    if Minutes >= 60 then
    begin
      var Heures := Minutes div 60;
      Dec(Minutes, 60 * Heures);
      Result := Heures.ToString + ' heure';
      if Heures > 1 then
        Result := Result + 's';
    end;
    if Minutes > 0 then
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Minutes.ToString + ' min';
      if Minutes > 1 then
        Result := Result + 's';
    end;
  end;
  if (Seconds > 0) or (Result = '') then
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Seconds.ToString + ' s';
  end;
end;

type
  TTask = class
  private
    FThread: TThread;
  public
    procedure Synchronize(AMethod: TThreadMethod);
    procedure Execute(); virtual; abstract;
    procedure Submit();
  end;

  TTaskThread = class(TThread)
  private
    FTask: TTask;
  public
    constructor Create(ATask: TTask);
    procedure Execute; override;
  end;

  TTokenRequest = record
    app_id: string;
    app_name: string;
    app_version: string;
    device_name: AnsiString;
  end;

  TSessionStart = record
    app_id: string; // UTF8String;
    app_version: string; // UTF8String;
    password: UTF8String; // HMAC_SHA1(app_token, challenge)
  end;

  // {"msg":"Invalid request: cannot parse json","success":false,"error_code":"invalid_request"}
  TFreeboxResponse = record
    success: Boolean;
    msg: string;
    error_code: string;
    result: TJSONRawValue;
  end;

  // '{"success":true,"result":{"app_token":"O9NdSLo9URg...rcT6TR","track_id":1}}'
  TTokenResult = record
    app_token: UTF8String;
    track_id: string; // Integer;
  end;

  // {"success":true,"result":{"status":"pending","challenge":"bfk9QV5...6bTsQDsYKAa","password_salt":"TJe37EJ...NX3U10P7"}}
  TAuthorization = record
    status: UTF8String; // (unknown, pending, timeout, granted, denied);
    challenge: UTF8String;
    password_salt: UTF8String;
  end;

  TChallengeResult = record
    logged_in: Boolean;
    challenge: UTF8String;
  end;

  (*
   {"result":
    {"session_token":"xlL8YY3v...q+xAs1",
     "challenge":"NoCPeh0h7...FuI+D6FcvYo8",
     "password_salt":"TJe37EJ...NX3U10P7",
     "permissions":{
      "parental":false,
      "tv":true,
      "explorer":true,
      "contacts":true,
      "wdo":false,
      "camera":false,
      "profile":false,
      "player":false,
      "settings":false,
      "calls":true,
      "home":false,
      "pvr":true,
      "vm":true,
      "downloader":true},
     "password_set":true},
    "success":true}
  *)
  TPermissions = record
    parental: Boolean;
    tv: Boolean;
    explorer: Boolean;
    contacts: Boolean;
    wdo: Boolean;
    camera: Boolean;
    profile: Boolean;
    player: Boolean;
    settings: Boolean;
    calls: Boolean;
    home: Boolean;
    pvr: Boolean;
    vm: Boolean;
    downloader: Boolean;
  end;
  TSessionResult = record
    session_token: string;
    challenge: UTF8String;
    permissions: TPermissions;
    password_set: Boolean;
  end;

  TFreeboxTask = class(TTask)
  private
    Freebox: TFreeboxOS;
    FApp: TTokenRequest;
    FURL: string;
    FAppToken: UTF8String;
    FChallenge: UTF8String;
    FSessionToken: UTF8String;
    FHTTP: THTTPClient;
    FResp: IHTTPResponse;
    FError: string;
    FErrNo: string;
    FDescr: string;
    FDetails: string;
    procedure OnError;
    procedure OnVersion;
    procedure OnPending;
    procedure OnToken;
    procedure OnSession;
    function Post(const URI: string; const Data: UTF8String; var Response: UTF8String): Boolean;
    function Get(const URI: string; var Response: UTF8String): Boolean;
    function GetResponse(const URI: string; var Response: UTF8String): Boolean;
    procedure RegisterApplication;
    function TryOpenSession: Boolean;
    procedure OpenSession;
    procedure GetAuthStatus(const TrackID: string; var Status: TAuthorization);
    function GetChallenge: UTF8String;
  public
    constructor Create(AFreebox: TFreeboxOS; ASync: Boolean);
    procedure Execute; override;
  end;

  TGetCallsTask = class(TFreeboxTask)
  private
    FCalls: TCallEntries;
    procedure OnCalls;
  public
    procedure Execute; override;
  end;

{ TTask }

procedure TTask.Synchronize(AMethod: TThreadMethod);
begin
  if FThread = nil then
    AMethod()
  else
    TThread.Synchronize(FThread, AMethod);
end;

procedure TTask.Submit;
begin
  FThread := TTaskThread.Create(Self);
end;

{ TTaskThread }

constructor TTaskThread.Create(ATask: TTask);
begin
  FTask := ATask;
  inherited Create;
  FreeOnTerminate := True;
end;

procedure TTaskThread.Execute();
begin
  try
    FTask.Execute;
  finally
    FTask.Free;
  end;
end;

{ TFreeboxTask }

function HostName: AnsiString;
begin
  SetLength(Result, 50);
  if gethostname(PAnsiChar(Result), 50) = SOCKET_ERROR then
    Exit('Delphi')
  else
    Result := PAnsiChar(Result);
end;

constructor TFreeboxTask.Create(AFreebox: TFreeboxOS; ASync: Boolean);
begin
  inherited Create;

  Freebox := AFreeBox;

  FApp.app_id := Freebox.AppId;
  FApp.app_name := Freebox.AppName;
  FApp.app_version := Freebox.FAppVersion;

  FURL := Freebox.FURL;
  FAppToken := Freebox.FAppToken;
  FSessionToken := Freebox.FSessionToken;

  FHTTP := THTTPClient.Create;
  if ASync then
    Submit()
  else begin
    Execute();
    Free(); // do not capture any Exception ! Delphi will free this instance in that case
  end;
end;

procedure TFreeboxTask.Execute;
begin
{$IFDEF FREEBOX_LOG}AllocConsole;{$ENDIF}
  // First, we need to find the Freebox
  if FURL = '' then
  begin
    {$IFDEF FREEBOX_LOG}WriteLn('GET http://mafreebox.freebox.fr/api_version');{$ENDIF}
    FResp := FHTTP.Get('http://mafreebox.freebox.fr/api_version');
    {$IFDEF FREEBOX_LOG}WriteLn(FResp.StatusCode, ' ', FResp.StatusText); WriteLn(FResp.ContentAsString(TEncoding.UTF8)); WriteLn;{$ENDIF}
    if FResp.StatusCode <> 200 then
    begin
      FError := 'La Freebox n''est pas joignable';
      FDescr := 'Réponse inattendue de "http://mafreebox.freebox.fr"';
      FDetails := FResp.StatusCode.ToString + ' ' + FResp.StatusText;
      Synchronize(OnError);
      Abort;
    end;
    Synchronize(OnVersion);
  end;

  // Is the application registered ?
  if FAppToken = '' then
  begin
    RegisterApplication();
  end;

  // Is the session active ?
  if FSessionToken = '' then
  begin
    OpenSession();
  end;

  FHTTP.CustomHeaders['X-Fbx-App-Auth'] := FSessionToken;
end;

procedure TFreeboxTask.OnError;
begin
  if Assigned(Freebox.OnError) then
    Freebox.OnError(Freebox, FError, FDescr, FDetails)
  else begin
    var Dlg := TTaskDialog.Create(nil);
    Dlg.Caption := 'FreeboxOS';
    Dlg.Title := FError;
    Dlg.Caption := FDescr;
    Dlg.ExpandedText := FDetails;
    Dlg.Execute;
  end;
end;

procedure TFreeboxTask.OnVersion;
begin
  JSON.fromJSON(Freebox.FVersion, FResp.ContentAsString(TEncoding.UTF8));
  var v := Freebox.Version.api_version;
  var i := Pos('.', v);
  SetLength(v, i - 1);
  FURL := 'http://mafreebox.freebox.fr' + Freebox.version.api_base_url + 'v' + v + '/';
  Freebox.SetURL(FURL);
  FAppToken := Freebox.FAppToken;
end;

procedure TFreeboxTask.OnPending;
begin
  if Assigned(Freebox.OnPending) then
    Freebox.OnPending(FreeBox);
end;

procedure TFreeboxTask.OnToken;
begin
  Freebox.FAppToken := FAppToken;
  if Assigned(Freebox.OnGranted) then
    FreeBox.OnGranted(Freebox);
  if ASsigned(Freebox.OnSaveAppToken) then
    Freebox.OnSaveAppToken(FreeBox, Freebox.Version.uid, FAppToken);
end;

procedure TFreeboxTask.OnSession;
begin
  Freebox.FSessionToken := FSessionToken;
end;

function TFreeboxTask.Post(const URI: string; const Data: UTF8String; var Response: UTF8String): Boolean;
begin
  var P := TPointerStream.Create(Pointer(Data), Length(Data));
  var R := TMemoryStream.Create;
  try
  {$IFDEF FREEBOX_LOG}WriteLn('POST ', FURL, URI); WriteLn(Data);{$ENDIF}
    FResp := FHTTP.Post(FURL + URI, P, R);
    SetString(Response, PAnsiChar(R.Memory), R.Size);
    Result := GetResponse(URI, Response);
  finally
    R.Free;
    P.Free;
  end;
end;

function TFreeboxTask.Get(const URI: string; var Response: UTF8String): Boolean;
begin
  {$IFDEF FREEBOX_LOG}WriteLn('GET ', FURL, URI); WriteLn(FHTTP.CustHeaders.ToString); {$ENDIF}
  FResp := FHTTP.Get(FURL + URI);
  Response := FResp.ContentAsString(TEncoding.UTF8);
  Result := GetResponse(URI, Response);
end;

function TFreeboxTask.GetResponse(const URI: string; var Response: UTF8String): Boolean;
begin
 {$IFDEF FREEBOX_LOG}WriteLn(FResp.StatusCode, ' ', FResp.StatusText); WriteLn(Response); WriteLn;{$ENDIF}
  Result := False;
  FError := '';
  FErrNo := '';
  FDescr := '';
  FDetails := '';
  if (FResp.StatusCode <> 200) and (Pos('success', Response) = 0) then
  begin
    FError := 'Une erreur s''est produit lors de l''appel à la Freebox';
    FDescr := FResp.StatusCode.ToString  + ' ' + FResp.StatusText;
    FDetails := FURL + URI;
    Exit;
  end;
  var M: TFreeboxResponse;
  JSON.fromJSON(M, Response);
  if M.success = True then
  begin
    Response := M.result;
    Result := True;
  end else begin
    FError := 'Réponse inattendue de la Freebox';
    FErrNo := M.error_code;
    FDescr := M.msg + ' (' + M.error_code + ')';
    FDetails := FURL + URI;
    Result := False;
  end;
end;

procedure TFreeboxTask.RegisterApplication;
begin
  FApp.device_name := HostName();
  var S: UTF8String;
  if not Post('login/authorize/', JSON.toJSON(FApp), S) then
  begin
    FError := 'Impossible d''enregistrer l''application sur la Freebox';
    Synchronize(OnError);
    Abort;
  end;
  var Token: TTokenResult;
  JSON.fromJSON(Token, S);
  var Auth: TAuthorization;
  GetAuthStatus(Token.track_id, Auth);
  if Auth.status = 'pending' then
  begin
    Synchronize(OnPending);
    repeat
      Sleep(100);
      GetAuthStatus(Token.track_id, Auth);
    until Auth.status <> 'pending';
    if Auth.status <> 'granted' then
    begin
      FError := 'L''accès à la Freebox a été refusé';
      FDescr := Auth.status;
      FDetails := FURL + 'login/authorize/' + Token.track_id;
      Abort;
    end;
  end;

  FAppToken := Token.app_token;
  FChallenge := Auth.challenge;
  Synchronize(OnToken);
end;

procedure TFreeboxTask.GetAuthStatus(const TrackID: string; var Status: TAuthorization);
begin
  var S: UTF8String;
  if not Get('login/authorize/' + TrackID, S) then
  begin
    FError := 'Erreur de lecture de la réponse d''authorisation';
    Synchronize(OnError);
    Abort;
  end;
  JSON.fromJSON(Status, S);
end;

function TFreeboxTask.GetChallenge: UTF8String;
begin
  if FChallenge = '' then
  begin
    var S: UTF8String;
    if not Get('login/', S) then
    begin
      Synchronize(OnError);
      Abort;
    end;
    var reply: TChallengeResult;
    JSON.fromJSON(reply, S);
    FChallenge := reply.challenge;
  end;
  Result := FChallenge;
end;

function TFreeboxTask.TryOpenSession: Boolean;
begin
  var login: TSessionStart;
  login.app_id := FApp.app_id;
  login.app_version := FApp.app_version;
  login.password := HMAC_SHA1_Hexa(FAppToken, GetChallenge());

  var S: UTF8String;
  Result := Post('login/session/', JSON.toJSON(login), S);

  if Result then
  begin
    var resp: TSessionResult;
    JSON.fromJSON(resp, S);
    FSessionToken := resp.session_token;
    Synchronize(OnSession);
  end;
end;

procedure TFreeboxTask.OpenSession;
begin
  if not TryOpenSession then
  begin
    if FErrNo = 'auth_required' then
    begin
      FChallenge := ''; // renew Challenge
      if TryOpenSession() then
        Exit;
    end else
    if FErrNo = 'invalid_token'  then
    begin
      RegisterApplication; // revoked ?
      if TryOpenSession() then
        Exit;
    end;
    FError := 'Erreur lors de l''ouverture de la session';
    Synchronize(OnError);
    Abort;
  end;
end;

{ TGetCallsTask }

procedure TGetCallsTask.OnCalls;
begin
  if Assigned(Freebox.OnCalls) then
    Freebox.OnCalls(Freebox, FCalls);
end;

procedure TGetCallsTask.Execute;
begin
  inherited; // authentifcation etc...
  var S: UTF8String;
  if not Get('call/log/', S) then
  begin
    FError := 'Impossible de lire le journal d''appel';
    Synchronize(OnError);
    Abort;
  end;
  JSON.fromJSON(FCalls, S);
  for var I := 1 to Length(FCalls) - 1 do
  begin
    for var J := 0 to I - 1 do
    begin
      if FCalls[J].number = FCalls[I].number then
      begin
        Inc(FCalls[J].count);
        FCalls[I].count := FCalls[J].count;
      end;
    end;
  end;
  Synchronize(OnCalls);
end;

{ TFreeboxOS }

procedure TFreeboxOS.GetCalls(ASync: Boolean = True);
begin
  TGetCallsTask.Create(Self, ASync);
end;

procedure TFreeboxOS.SetURL(const AURL: string);
begin
  FURL := AURL;
  FAppToken := '';
  if Assigned(OnVersion) then
    OnVersion(Self);
  if Assigned(OnLoadAppToken) then
    OnLoadAppToken(Self, FVersion.uid, FAppToken);
end;

end.
