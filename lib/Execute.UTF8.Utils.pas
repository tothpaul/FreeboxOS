unit Execute.UTF8.Utils;

interface

uses
  System.SysUtils;

function Base64Len(Src: PByte; Len: Integer): Integer;
procedure Base64Decode(Src, Dst: PByte; Len: Integer); overload;
function Base64Decode(const Str: string): TBytes; overload;

function Base64Encode(const Str: UTF8String): UTF8String; overload;
function Base64Encode(Bytes: TBytes): UTF8String; overload; inline;
function Base64Encode(Data: PByte; Len: Integer): UTF8String; overload;
function Base64FromFile(const AFileName: string): UTF8String;
function Base64EncodeLen(Data: PByte; Len: Integer; LineLength: Integer = 76): UTF8String;

function DetectUF8(Ptr: PByte; Size: Integer): Boolean;

function IntToUTF8(Int: Integer): UTF8String;
function SizeToStr(Size: Integer): UTF8String;
function UTF8ToFloatDef(const Str: UTF8String; Default: Extended): Extended;

function Pos(const SubStr, Str: UTF8String; Start: Integer = 1): Integer;

function UTF8Trunc(const Str: UTF8String; EndChar: AnsiChar): UTF8String;
function UTF8Extract(const Str: UTF8String; FromChar, ToChar: AnsiChar): UTF8String;

implementation

const
  B64: array[0..63] of AnsiChar = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
var
  V64: array of Byte;

function NextB64(var P: PByte): Byte;
begin
  while P^ in [9, 10, 13, 32] do
    Inc(P);
  Result := V64[P^];
  Inc(P);
end;

procedure Base64Decode(Src, Dst: PByte; Len: Integer);
var
  i, a, b: Integer;
begin
  if V64 = nil then
  begin
    SetLength(V64, 256);
    FillChar(V64[0], 256, 0);
    for i := 0 to 63 do
      V64[Ord(B64[i])] := i;
  end;

  while Len >= 3 do
  begin
    a := NextB64(Src);
    b := NextB64(Src);
    Dst^ := (a shl 2) or (b shr 4); // ..765431 | ..10xxxx
    Inc(Dst);
    a := NextB64(Src);
    Dst^ := (b shl 4) or (a shr 2); // ..xx7654 | ..3210xx
    Inc(Dst);
    b := NextB64(Src);
    Dst^ := (a shl 6) or b;         // ..xxxx76 | ..543210
    Inc(Dst);
    Dec(Len, 3);
  end;

  if Len > 0 then
  begin
    a := NextB64(Src);
    b := NextB64(Src);
    Dst^ := (a shl 2) or (b shr 4); // ..765431 | ..10xxxx
    if Len > 1 then
    begin
      a := NextB64(Src);
      Inc(Dst);
      Dst^ := (b shl 4) or (a shr 2);  // ..xx7654 | ..3210xx
    end;
  end;
end;

function Base64Decode(const Str: string): TBytes; overload;
var
  Src: TBytes;
  Len: Integer;
begin
  Src := TEncoding.ANSI.GetBytes(Str);
  Len := Base64Len(PByte(Src), Length(Src));
  SetLength(Result, Len);
  Base64Decode(PByte(Src), PByte(Result), Len);
end;

function Base64Encode(const Str: UTF8String): UTF8String;
begin
  Result := Base64Encode(Pointer(Str), Length(Str));
end;

function Base64Encode(Bytes: TBytes): UTF8String;
begin
  Result := Base64Encode(PByte(Bytes), Length(Bytes));
end;

function Base64Encode(Data: PByte; Len: Integer): UTF8String;
var
  Index : Integer;
  Value : PByte;
  Chars : PAnsiChar;
  C1, C2: Integer;
begin
  SetLength(Result, 4 * ((Len + 2) div 3));
  Index := 1;
  Value := Data;
  Chars := @Result[1];
  while Index < Len - 2 do
  begin
    C1 := Value^;
    Inc(Value);
    C2 := Value^;
    Inc(Value);
    Chars^ := B64[C1 shr 2];
    Inc(Chars);
    Chars^ := B64[((C1 and 3) shl 4) or (C2 shr 4)];
    Inc(Chars);
    C1 := Value^;
    Inc(Value);
    Chars^ := B64[((C2 and $0F) shl 2) or (C1 shr 6)];
    Inc(Chars);
    Chars^ := B64[C1 and $3F];
    Inc(Chars);
    Inc(Index, 3);
  end;
  if Index <= Len then
  begin
    C1 := Value^;
    Inc(Index);
    if Index > Len then
      C2 := 0
    else begin
      Inc(Value);
      C2 := Value^;
    end;
    Chars^ := B64[C1 shr 2];
    Inc(Chars);
    Chars^ := B64[((C1 and 3) shl 4) or (C2 shr 4)];
    Inc(Chars);
    if Index > Len then
      Chars^ := '='
    else begin
      Inc(Index);
      if Index > Len then
        C1 := 0
      else begin
        Inc(Value);
        C1 := Value^;
      end;
      Chars^ := B64[((C2 and $0F) shl 2) or (C1 shr 6)];
    end;
    Inc(Chars);
    if Index > Len then
      Chars^ := '='
    else begin
      Chars^ := B64[C1 and $3F];
    end;
  end;
end;

function Base64EncodeLen(Data: PByte; Len: Integer; LineLength: Integer = 76): UTF8String;
var
  LLen  : Integer;
  Index : Integer;
  Value : PByte;
  Chars : PAnsiChar;
  C1, C2: Integer;

  procedure NewLine;
  begin
//    Chars[LLen] := #13;
//    Inc(LLen);
    Chars[LLen] := #10;
    Inc(LLen);
    Inc(Chars, LLen);
    LLen := 0;
  end;

  procedure AddChar(Ch: AnsiChar);
  begin
    if LLen = LineLength then
      NewLine;
    Chars[LLen] := Ch;
    Inc(LLen);
  end;

begin
  Index := 4 * ((Len + 2) div 3);
  Inc(Index, ((Index + LineLength - 1) div LineLength));
  SetLength(Result, Index);
  Index := 1;
  Value := Data;
  Chars := @Result[1];
  LLen := 0;
  while Index < Len - 2 do
  begin
    C1 := Value^;
    Inc(Value);
    C2 := Value^;
    Inc(Value);
    AddChar(B64[C1 shr 2]);
    AddChar(B64[((C1 and 3) shl 4) or (C2 shr 4)]);
    C1 := Value^;
    Inc(Value);
    AddChar(B64[((C2 and $0F) shl 2) or (C1 shr 6)]);
    AddChar(B64[C1 and $3F]);
    Inc(Index, 3);
  end;
  if Index <= Len then
  begin
    C1 := Value^;
    Inc(Index);
    if Index > Len then
      C2 := 0
    else begin
      Inc(Value);
      C2 := Value^;
    end;
    AddChar(B64[C1 shr 2]);
    AddChar(B64[((C1 and 3) shl 4) or (C2 shr 4)]);
    if Index > Len then
      AddChar('=')
    else begin
      Inc(Index);
      if Index > Len then
        C1 := 0
      else begin
        Inc(Value);
        C1 := Value^;
      end;
      AddChar(B64[((C2 and $0F) shl 2) or (C1 shr 6)]);
    end;
    if Index > Len then
      AddChar('=')
    else begin
      AddChar(B64[C1 and $3F]);
    end;
  end;
  if LLen > 0 then
    NewLine;
  Assert(Chars = @Result[Length(Result) + 1]);
end;

function Base64FromFile(const AFileName: string): UTF8String;
var
  f     : file;
  Total : Integer;
  Len   : Integer;
  Index : Integer;
  Value : PByte;
  Chars : PAnsiChar;
  C1, C2: Integer;
  Buffer: array[0..767] of Byte; // (768 / 3) * 4 = 1024
begin
  Assignfile(f, AFileName);
  Reset(f, 1);
  try
    Total := FileSize(f);
    SetLength(Result, 4 * ((Total + 2) div 3));
    Chars := @Result[1];
    while Total > 0 do
    begin
      BlockRead(f, Buffer, SizeOf(Buffer), Len);
      Dec(Total, Len);
      Value := @Buffer;
      Index := 1;
      while Index < Len - 2 do
      begin
        C1 := Value^;
        Inc(Value);
        C2 := Value^;
        Inc(Value);
        Chars^ := B64[C1 shr 2];
        Inc(Chars);
        Chars^ := B64[((C1 and 3) shl 4) or (C2 shr 4)];
        Inc(Chars);
        C1 := Value^;
        Inc(Value);
        Chars^ := B64[((C2 and $0F) shl 2) or (C1 shr 6)];
        Inc(Chars);
        Chars^ := B64[C1 and $3F];
        Inc(Chars);
        Inc(Index, 3);
      end;
      if Index <= Len then
      begin
        C1 := Value^;
        Inc(Index);
        if Index > Len then
          C2 := 0
        else begin
          Inc(Value);
          C2 := Value^;
        end;
        Chars^ := B64[C1 shr 2];
        Inc(Chars);
        Chars^ := B64[((C1 and 3) shl 4) or (C2 shr 4)];
        Inc(Chars);
        if Index > Len then
          Chars^ := '='
        else begin
          Inc(Index);
          if Index > Len then
            C1 := 0
          else begin
            Inc(Value);
            C1 := Value^;
          end;
          Chars^ := B64[((C2 and $0F) shl 2) or (C1 shr 6)];
        end;
        Inc(Chars);
        if Index > Len then
          Chars^ := '='
        else begin
          Chars^ := B64[C1 and $3F];
        end;
      end;
    end;
  finally
    CloseFile(f);
  end;
end;


procedure TrimR(Src: PByte; var Len: Integer);
begin
  while Src[Len - 1] in [9, 10, 13, 32] do
    Dec(Len);
end;

function Base64Len(Src: PByte; Len: Integer): Integer;
var
  Index: Integer;
begin
// Trim right
  TrimR(Src, Len);
// ignore any spaces
  Result := Len;
  for Index := 0 to Len - 1 do
  begin
    if Src[Index] in [9, 10, 13, 32] then
      Dec(Result);
  end;
// compute decoded size
  Result := (3 * Result) div 4;
// check last two chars (of the right trimed text)
  if Src[Len - 1] = Ord('=') then
  begin
    Dec(Result);
    Dec(Len);
    TrimR(Src, Len);
    if Src[Len - 1] = Ord('=') then
      Dec(Result);
  end;
end;

function DetectUF8(Ptr: PByte; Size: Integer): Boolean;
var
  Index: Integer;
  C1   : Byte;
  C2   : Byte;
  C3   : Byte;
begin
  Result := False;
  C2 := 0; // UTF8Sequence not found
  Index := 0;
  while Index < Size do
  begin
  {
      $00..$7F

      $C2..$DF + $80..$BF

      $E0      + $A0..$BF + $80..$BF
      $E1..$EC + $80..$BF + $80..$BF
      $ED      + $80..$9F + $80..$BF
      $EE..$EF + $80..$BF + $80..$BF

      $F0      + $90..$BF + $80..$BF + $80..$BF
      $F1..$F3 + $80..$BF + $80..$BF + $80..$BF
      $F4      + $80..$8F + $80..$BF + $80..$BF
  }
    C1 := Ptr[Index];
    Inc(Index);
    case C1 of
      $00..$7F: { ASCII } ;
      $C2..$F4: // UTF8 compatible
      begin
        if Index = Size then
          Exit; // need a second byte
        C2 := Ptr[Index];
        if (C2 < $80) or (C2 > $BF) then
          Exit; // invalid UTF8 Sequence
        Inc(Index);
        if C1 >= $E0 then // more then 2 chars
        begin
          if Index = Size then // 3 chars sequence
            Exit;
          if (C1 = $E0) and (C2 < $A0) then
            Exit;
          if (C1 = $ED) and (C2 > $9F) then
            Exit;
          if (C1 = $F0) and (C2 < $90) then
            Exit;
          C3 := Ptr[Index];
          if (C3 < $80) or (C3 > $BF) then
            Exit; // invalid UTF8 Sequence
          Inc(Index);
          if C2 >= $F0 then
          begin
            if Index = Size then
              Exit; // 4 chars sequence
            C3 := Ptr[Index];
            if (C3 < $80) or (C3 > $BF) then
              Exit; // invalid UTF8 Sequence
            Inc(Index);
          end;
        end;
      end;
    else
      Exit(False); // UTF8 incompatible
    end;
  end;
  Result := C2 <> 0; // UTF8 compatible
end;

function IntToUTF8(Int: Integer): UTF8String;
var
  S: AnsiString;
begin
  Str(Int, S);
  Result := UTF8String(S);
end;

function SizeToStr(Size: Integer): UTF8String;
var
  Kind: UTF8String;
begin
  if Size = 0 then
    Exit('vide');
  if Size < 1024 then
  begin
    Kind := ' octets';
  end else begin
    Size := (Size + 512) div 1024;
    if Size < 1024 then
      Kind := ' Ko'
    else begin
      Size := (Size + 512) div 1024;
      if Size < 1024 then
        Kind := ' Mo'
      else begin
        Size := (Size + 512) div 1024;
        Kind := ' Go';
      end;
    end;
  end;
  Str(Size, AnsiString(Result));
  Result := Result + Kind;
end;

function UTF8ToFloatDef(const Str: UTF8String; Default: Extended): Extended;
var
  LStr: string;
begin
  LStr := string(Str).Replace('.', FormatSettings.DecimalSeparator);
  Result := System.SysUtils.StrToFloatDef(LStr, Default);
end;

function Pos(const SubStr, Str: UTF8String; Start: Integer = 1): Integer;
var
  L1: Integer;
  L2: Integer;
  B1: PAnsiChar;
  B2: PAnsiChar;
  I: Integer;
  J: Integer;
begin
  L2 := Length(SubStr);
  if L2 = 0 then
    Exit(0);
  L1 := Length(Str) - L2 + 1;
  if Start > 1 then
  begin
    Dec(L1, Start - 1);
    if L1 = 0 then
      Exit(0);
  end else begin
    Start := 1;
  end;
  B1 := @Str[Start];
  B2 := Pointer(SubStr);
  for I := 1 to L1 do
  begin
    J := 0;
    while B1[J] = B2[J] do
    begin
      Inc(J);
      if J = L2 then
        Exit(I + Start - 1);
    end;
    Inc(B1);
  end;
  Result := 0;
end;

function UTF8Trunc(const Str: UTF8String; EndChar: AnsiChar): UTF8String;
var
  Index: Integer;
begin
  for Index := 1 to Length(Str) do
  begin
    if Str[Index] = EndChar then
    begin
      Result := Copy(Str, 1, Index - 1);
      Exit;
    end;
  end;
  Result := '';
end;

function UTF8Extract(const Str: UTF8String; FromChar, ToChar: AnsiChar): UTF8String;
var
  Start, Stop: Integer;
begin
  for Start := 1 to Length(Str) do
  begin
    if Str[Start] = FromChar then
    begin
      for Stop := Start + 1 to Length(Str) do
      begin
        if Str[Stop] = ToChar then
          Exit(Copy(Str, Start + 1, Stop - Start - 1));
      end;
    end;
  end;
  Result := '';
end;

procedure test;
var
  s: string;
  u: UTF8String;
begin
  Assert(Base64Encode('test') = 'dGVzdA==');
  Assert(TEncoding.ANSI.GetString(Base64Decode('dGVzdA==')) = 'test');
  s := 'Hello There';
  u := 'Hello There';
  assert(Pos('Hello', u) = 1);
  assert(Pos('Hello', u) = System.Pos('Hello', s));
  assert(Pos('There', u) = 7);
  assert(Pos('There', u) = System.Pos('There', s));
  assert(Pos('no', u)    = System.Pos('no', s));
  assert(Pos('e', u)     = System.Pos('e', s));
  assert(Pos('e', u, 4)  = System.Pos('e', s, 4));
  assert(Pos('H', u, 4)  = System.Pos('H', s, 4));
end;

initialization
{$ifdef debug}
//test();
{$endif}
end.
