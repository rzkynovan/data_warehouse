show databases;

drop schema if exists frs_proses;
create schema frs_proses;

use frs_proses;

drop table if exists Periode;
create table Periode (
    id bigint unsigned auto_increment primary key,
    nama enum ('Genap', 'Ganjil') not null,
    tahun year,
    tanggal_mulai datetime not null,
    tanggal_berakhir datetime not null,
    created_at datetime default NOW(),
    updated_at datetime default NOW()

);

drop table if exists Jenjang;
create table Jenjang(
    id bigint unsigned auto_increment primary key,
    nama varchar(255) not null
);

drop table if exists Fakultas;
create table Fakultas (
    id bigint unsigned auto_increment primary key,
    nama varchar(255) not null,
    created_at datetime default NOW(),
    updated_at datetime default NOW()
);

drop table if exists Departemen;
create table Departemen (
    id bigint unsigned auto_increment primary key,
    nama varchar(255) not null,
    created_at datetime default NOW(),
    updated_at datetime default NOW(),
    fakultas_id bigint unsigned not null,
    foreign key (fakultas_id) references Fakultas(id)
);

drop table if exists ProgramStudi;
create table ProgramStudi(
    id bigint unsigned auto_increment primary key,
    name varchar(255) not null,
    kapasitas int(4) not null,
    akreditasi enum ('Unggul', 'A', 'B', 'C'),
    created_at datetime default NOW(),
    updated_at datetime default NOW(),
    departemen_id bigint unsigned not null,
    jenjang_id bigint unsigned not null,
    foreign key (departemen_id) references Departemen(id),
    foreign key (jenjang_id) references Jenjang(id)
);



drop table if exists Dosen;
create table Dosen(
    id bigint unsigned auto_increment primary key,
    nama varchar(255) not null,
    nidn varchar(255) not null,
    dosen_aktif bool default true,
    alamat text,
    pendidikan_terakhir enum( 'S1','S2', 'S3'),
    created_at datetime default NOW(),
    updated_at datetime default NOW()
);

drop table if exists Mahasiswa;
create table Mahasiswa (
    id bigint unsigned auto_increment primary key,
    nama varchar(255) not null,
    alamat text,
    mahasiswa_aktif bool default true,
    created_at datetime default NOW(),
    updated_at datetime default NOW(),
    programstudi_id bigint unsigned not null,
    dosen_wali_id bigint unsigned not null,
    foreign key (programstudi_id) references ProgramStudi(id),
    foreign key (dosen_wali_id) references Dosen(id)
);

drop table if exists MataKuliah;
create table MataKuliah(
    id bigint unsigned auto_increment primary key,
    nama varchar(255) not null,
    sks tinyint(1) unsigned not null check(sks between 2 and 6),
    created_at datetime default NOW(),
    updated_at datetime default NOW(),
    programstudi_id bigint unsigned not null,
    foreign key (programstudi_id) references ProgramStudi(id)
);

drop table if exists Kelas;
create table Kelas(
    id bigint unsigned auto_increment primary key,
    nama varchar(255) not null,
    kelas_mbkm bool default false,
    kelas_pengayaan bool default false,
    kapasitas int,
    jenjang enum('D4', 'S1', 'S2', 'S3') not null,
    created_at datetime default NOW(),
    updated_at datetime default NOW(),
    matakuliah_id bigint unsigned not null,
    dosen_utama_id bigint unsigned,
    jenjang_id bigint unsigned not null,
    foreign key (matakuliah_id) references MataKuliah(id),
    foreign key (dosen_utama_id) references Dosen(id),
    foreign key (jenjang_id) references Jenjang(id),
    check (kelas_mbkm = true or (kapasitas between 1 and 40)),
    check ((kelas_mbkm = false and dosen_utama_id is not null) or (kelas_mbkm = true))
);

drop table if exists TeamTeaching;
create table TeamTeaching(
    id bigint unsigned auto_increment primary key,
    dosen_id bigint unsigned not null,
    kelas_id bigint unsigned not null,
    foreign key (dosen_id) references Dosen(id),
    foreign key (kelas_id) references Kelas(id)

);

drop table if exists FRS;
create table FRS(
    id bigint unsigned auto_increment primary key,
    nama varchar(255) not null,
    status enum('Diajukan', 'Disetujui', 'Ditolak'),
    kelas_id bigint unsigned not null,
    mahasiswa_id bigint unsigned not null,
    periode_id bigint unsigned not null,
    foreign key (kelas_id) references Kelas(id),
    foreign key (mahasiswa_id) references Mahasiswa(id),
    foreign key (periode_id) references Periode(id)
);

drop table if exists PerencanaanSKEM;
create table PerencanaanSkem(
    id bigint unsigned auto_increment primary key,
    status enum('Diajukan', 'Disetujui', 'Ditolak'),
    mahasiswa_id bigint unsigned not null,
    periode_id bigint unsigned not null,
    foreign key (mahasiswa_id) references Mahasiswa(id),
    foreign key (periode_id) references Periode(id)
);

drop table if exists PerencanaanMBKM;
create table PerencanaanMBKM(
    id bigint unsigned auto_increment primary key,
    status enum('Diajukan', 'Disetujui', 'Ditolak'),
    mahasiswa_id bigint unsigned not null,
    periode_id bigint unsigned not null,
    foreign key (mahasiswa_id) references Mahasiswa(id),
    foreign key (periode_id) references Periode(id)
);



delimiter $$
drop trigger if exists cek_sks_mahasiswa;
create trigger cek_sks_mahasiswa before insert on FRS
    for each row
    begin
        declare total_sks tinyint unsigned;
        select SUM(mk.sks) into total_sks
        from FRS as f
        join Kelas as k on f.kelas_id = k.id
        join MataKuliah as mk on k.matakuliah_id = mk.id
        where f.mahasiswa_id = NEW.mahasiswa_id and f.periode_id = NEW.periode_id;

        select total_sks + (
            select sks from MataKuliah as mk
                join Kelas as k on mk.id = k.matakuliah_id
                       where k.id = NEW.id
            ) into total_sks;

        if total_sks > 24 then
            signal sqlstate '45000'
            set message_text = 'Maksimal SKS yang dapat anda ambil adalah 24';
        end if;

    end $$

drop trigger if exists cek_mk_dapat_diambil;
create trigger cek_mk_dapat_diambil before insert on FRS
    for each row
    begin
        declare apakah_kelas_mbkm bool;
        declare apakah_kelas_pengayaan bool;
        declare mk_prodi bigint unsigned;
        declare mahasiswa_prodi bigint unsigned;
        declare kelas_jenjang bigint unsigned;
        declare mahasiswa_jenjang bigint unsigned;

        select k.kelas_mbkm, k.kelas_pengayaan, jenjang_id
        into apakah_kelas_mbkm, apakah_kelas_pengayaan, kelas_jenjang
        from Kelas as k
        where k.id = NEW.kelas_id;

        select m.programstudi_id, ps.jenjang_id
        into mahasiswa_prodi, mahasiswa_jenjang
        from Mahasiswa as m
        join ProgramStudi as ps on m.programstudi_id = ps.id
        where m.id = NEW.mahasiswa_id;


        if apakah_kelas_mbkm then
            if kelas_jenjang != mahasiswa_jenjang then
                 signal sqlstate '45000'
                 set message_text = 'Mata kuliah tersebut tidak dibuka untuk jenjang anda';
            end if;
            elseif not apakah_kelas_pengayaan then
                select mk.programstudi_id
                into mk_prodi
                from MataKuliah as mk
                join Kelas as k on mk.id = k.matakuliah_id
                where k.id = NEW.kelas_id;

                if mk_prodi != mahasiswa_prodi then
                    signal sqlstate '45000'
                    set message_text = 'Mata kuliah tersebut tidak dibuka untuk prodi anda';
                end if;
        end if;
    end $$

drop trigger if exists cek_dapat_setujui_frs;
create trigger cek_dapat_setujui_frs before update on FRS
for each row
    begin
        declare perencanaan_skem enum('Diajukan', 'Disetujui', 'Ditolak');
        declare perencanaan_mbkm enum('Diajukan', 'Disetujui', 'Ditolak');

    if NEW.status = 'Disetujui' and OLD.status != 'Disetujui' then
        select ps.status
        into perencanaan_skem
        from PerencanaanSkem as ps
        where NEW.mahasiswa_id = ps.mahasiswa_id;


        select pm.status
        into perencanaan_mbkm
        from PerencanaanMBKM as pm
        where NEW.mahasiswa_id = pm.mahasiswa_id;

        if perencanaan_skem != 'Disetujui' or perencanaan_mbkm != 'Disetujui' then
            signal sqlstate '45000'
            set message_text = 'SKEM atau MBKM anda belum disetujui';
        end if;

    end if;
end $$

delimiter ;

