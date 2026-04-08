const std: type = @import("std");
const time: type = @cImport({
    @cInclude("time.h");
});

pub const Timestamp: type = i64;
pub const FormattedTimestampBuffer: type = [32]u8;

pub const DayName: type = enum {
    Sunday,
    Monday,
    Tuesday,
    Wednesday,
    Thursday,
    Friday,
    Saturday
};

pub const MonthName: type = enum {
    January,
    February,
    March,
    April,
    May,
    June,
    July,
    August,
    September,
    October,
    November,
    December
};

pub const DatetimeComponents: type = struct {
    year: i16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    millisecond: u16,
    dayName: DayName,
    monthName: MonthName
};

fn isLeapYear(year: i16) bool {
    return (@mod(year,4) == 0 and @mod(year,100) != 0) or @mod(year,400) == 0;
}

pub fn datetimeComponentsFromTimestamp(timestamp: Timestamp) DatetimeComponents {
    const timestampSeconds: isize = @divFloor(timestamp,std.time.ms_per_s);
    
    var timestampDays: isize = @divFloor(timestampSeconds,std.time.s_per_day);
    var secondInCurrentDay: u32 = @intCast(timestampSeconds - std.time.s_per_day * timestampDays);
    
    if (secondInCurrentDay < 0) {
        secondInCurrentDay += std.time.s_per_day;
        timestampDays -= 1;
    }
    
    const hour: u8 = @intCast(@divFloor(secondInCurrentDay,std.time.s_per_hour));
    const minute: u8 = @intCast(@divFloor(@mod(secondInCurrentDay,std.time.s_per_hour),60));
    const second: u8 = @intCast(@mod(secondInCurrentDay,60));
    
    var year: i16 = 1970;
    
    if (timestampDays >= 0) {
        while (true) {
            const daysInCurrentYear: isize = if (isLeapYear(year)) 366 else 365;
            
            if (timestampDays < daysInCurrentYear) {
                break;
            }
            
            timestampDays -= daysInCurrentYear;
            
            year += 1;
        }
    } else {
        while (true) {
            year -= 1;
            
            const daysInCurrentYear: isize = if (isLeapYear(year)) 366 else 365;
            
            timestampDays += daysInCurrentYear;
            
            if (timestampDays >= 0) {
                break;
            }
        }
    }
    
    var month: u8 = 1;
    
    while (true) {
        const daysInCurrentMonth: u8 = switch (month) {
            1 => 31,
            2 => if (isLeapYear(year)) 29 else 28,
            3 => 31,
            4 => 30,
            5 => 31,
            6 => 30,
            7 => 31,
            8 => 31,
            9 => 30,
            10 => 31,
            11 => 30,
            12 => 31,
            else => unreachable
        };
        
        if (timestampDays < daysInCurrentMonth) {
            break;
        }
        
        timestampDays -= daysInCurrentMonth;
        
        month += 1;
    }
    
    const day: u8 = @intCast(timestampDays + 1);
    
    return .{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
        .millisecond = @intCast(timestamp - timestampSeconds * std.time.ms_per_s),
        .dayName = @enumFromInt(@as(u8,@intCast(@mod((@divFloor(timestamp,std.time.ms_per_s * std.time.s_per_day) + 4),7)))),
        .monthName = @enumFromInt(month - 1)
    };
}

pub fn formatDatetime(buffer: *FormattedTimestampBuffer,timestamp: Timestamp) []u8 {
    const datetimeComponents: DatetimeComponents = datetimeComponentsFromTimestamp(timestamp);
    
    return std.fmt.bufPrint(
        buffer,
        "{s}{:04}-{:02}-{:02} @ {:02}:{:02}:{:02}",
        .{
            if (datetimeComponents.year < 0) "-" else "",
            @abs(datetimeComponents.year),
            datetimeComponents.month,
            datetimeComponents.day,
            datetimeComponents.hour,
            datetimeComponents.minute,
            datetimeComponents.second
        }
    ) catch unreachable;
}

pub fn formatDate(buffer: *FormattedTimestampBuffer,timestamp: Timestamp) []u8 {
    const datetimeComponents: DatetimeComponents = datetimeComponentsFromTimestamp(timestamp);
    
    return std.fmt.bufPrint(
        buffer,
        "{s}{:04}-{:02}-{:02}",
        .{
            if (datetimeComponents.year < 0) "-" else "",
            @abs(datetimeComponents.year),
            datetimeComponents.month,
            datetimeComponents.day
        }
    ) catch unreachable;
}

pub fn formatTime(buffer: *FormattedTimestampBuffer,timestamp: Timestamp) []u8 {
    const datetimeComponents: DatetimeComponents = datetimeComponentsFromTimestamp(timestamp);
    
    return std.fmt.bufPrint(
        buffer,
        "{:02}:{:02}:{:02}",
        .{
            datetimeComponents.hour,
            datetimeComponents.minute,
            datetimeComponents.second
        }
    ) catch unreachable;
}

// TODO: Make cross-platform

pub fn getLocalTimestamp() Timestamp {
    const utcNowTime: time.time_t = time.time(null);
    
    var localNowTimeComponents: time.tm = undefined;
    _ = time.localtime_r(&utcNowTime,&localNowTimeComponents);
    
    const universalTimestamp: Timestamp = std.time.milliTimestamp();
    
    return universalTimestamp + localNowTimeComponents.tm_gmtoff * std.time.ms_per_s;
}

pub fn getUniversalTimestamp() Timestamp {
    return std.time.milliTimestamp();
}
