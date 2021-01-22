/***
	한빛대학 학사관리 데이터베이스
	강원대학교 컴퓨터공학과
	201521897 김형준
***/
DROP DATABASE IF EXISTS hanbitunivDB;
CREATE DATABASE hanbitunivDB;
USE hanbitunivDB;

CREATE TABLE Professor -- 교수 테이블
(
	아이디 SMALLINT NOT NULL PRIMARY KEY AUTO_INCREMENT, 
	이름 VARCHAR(10) NOT NULL,
	나이 TINYINT NOT NULL,
	직위 ENUM('전임강사','조교수','부교수','정교수','명예교수',
    '연구교수','산학협력교수','시간강사','겸임교수','임상교수',
    '초빙교수','석좌교수') NOT NULL,
	연구분야 VARCHAR(10) NOT NULL,
    
    CHECK(나이 >= 0)
);

CREATE TABLE Dept -- 학과 테이블
(
	학과번호 SMALLINT NOT NULL PRIMARY KEY AUTO_INCREMENT, 
	학과이름 VARCHAR(10) NOT NULL UNIQUE,
	학과사무실 VARCHAR(20) UNIQUE,
	학과장 SMALLINT UNIQUE,
    
	FOREIGN KEY(학과장)	REFERENCES Professor(아이디) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Graduate -- 대학원생 테이블
(
	아이디 SMALLINT NOT NULL PRIMARY KEY AUTO_INCREMENT, 
	이름 VARCHAR(10) NOT NULL,
	나이 TINYINT NOT NULL,
	학위과정 ENUM('석사', '박사') NOT NULL,
	멘티 SMALLINT,
    전공학과 SMALLINT NOT NULL,
    
    CHECK(나이 >= 0),
    FOREIGN KEY(멘티) REFERENCES Graduate(아이디) ON DELETE CASCADE ON UPDATE CASCADE,
	FOREIGN KEY(전공학과) REFERENCES Dept(학과번호) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE Project -- 과제 테이블
(
	과제번호 SMALLINT NOT NULL PRIMARY KEY AUTO_INCREMENT, 
	지원기관 VARCHAR(20),
	개시일 DATE,
	종료일 DATE,
	예산액 INT,
    연구책임자 SMALLINT NOT NULL,

	CHECK(예산액 >= 0),   
	FOREIGN KEY(연구책임자) REFERENCES Professor(아이디) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE work_dept -- 근무 테이블 (교수와 학과 간의 관계)
(
	근무번호 SMALLINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    근무교수 SMALLINT NOT NULL,
    근무학과 SMALLINT NOT NULL,
    참여백분율 FLOAT DEFAULT 0.0,
    
    CHECK(참여백분율 >= 0.0 AND 참여백분율 <= 1.0),
    FOREIGN KEY(근무교수) REFERENCES Professor(아이디) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY(근무학과) REFERENCES Dept(학과번호) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE work_in -- 수행 테이블 (교수와 과제 간의 관계)
(
	수행번호 SMALLINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    수행교수 SMALLINT NOT NULL,
    수행과제 SMALLINT NOT NULL,
   
    FOREIGN KEY(수행교수) REFERENCES Professor(아이디) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY(수행과제) REFERENCES Project(과제번호) ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE work_prog-- 수행 테이블 (대학원생과 과제 간의 관계)
(
	수행번호 SMALLINT NOT NULL PRIMARY KEY AUTO_INCREMENT,
    수행대학원생 SMALLINT NOT NULL,
    수행과제 SMALLINT NOT NULL,
   
    FOREIGN KEY(수행대학원생) REFERENCES Graduate(아이디) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY(수행과제) REFERENCES Project(과제번호) ON DELETE CASCADE ON UPDATE CASCADE
);

/***
	참여백분율은 교수가 근무하는 학과마다 (해당 학과에 근무하는 교수의 수 / 근무(work_dept)
    에 참여하는 전체 교수의 수)의 비율에 따라 근무 릴레이션에 삽입, 수정, 삭제 작업 발생 시 자동 갱신 수행
    
    - 근무 릴레이션에 삽입, 삭제, 수정이 발생한 교수의 학과에 대하여 모두 변경사항 적용
	1) 각 학과에 근무하는 교수의 수
    : SELECT COUNT(*) FROM work_dept WHERE work_dept.근무학과 = NEW(OLD).근무학과;
    2) 학과에 참여하는 전체 교수의 수(즉, 근무 릴레이션의 전체 교수의 수)
    : SELECT COUNT(*) FROM work_dept;
    3) 구한 참여백분율은 변경사항이 발생한 학과에 대하여 모두 갱신
    : UPDATE work_dept SET pct_time = 위에서 구한 값 WHERE work_dept.근무학과 = NEW(OLD).근무학과;
    ---
    => 트리거 이벤트(INSERT, UPDATE, DELETE)가 실행된 테이블을 트리거를 통해 수정하려 하면 오류, 프로시저로 처리
    트리거는 매 이벤트(INSERT, UPDATE, DELETE)마다 동일하게 처리하여 적용하는 경우 사용하고 프로시저는 그렇지 않은 경우 사용
    ---
    !! work_dept에 새로운 데이터 삽입 혹은 변경 시 INSERT, UPDATE, DELETE를 사용하지 않고,
    사용자 정의 프로시저를 호출하여 수행(insert_work_dept, update_work_dept, delete_work_dept)
***/

DROP PROCEDURE IF EXISTS update_pct_time;
DELIMITER //
CREATE PROCEDURE update_pct_time()
BEGIN
   DECLARE total_work_dept_pf_cnt SMALLINT; -- 근무 릴레이션의 전체 교수의 수
   SELECT COUNT(*) INTO total_work_dept_pf_cnt FROM work_dept; -- 전체 근무에 참여하는 교수의 수
	-- 각 근무학과별로 그룹 지어 각 근무학과별 근무에 참여하는 교수의 수 / 전체 근무에 참여하는 교수의 수로 참여백분율 설정 (내부조인)
	UPDATE work_dept a
		INNER JOIN
		(SELECT 
			COUNT(*) grouped_cnt,
			근무학과
		FROM
			work_dept
		GROUP BY 근무학과) b
		ON a.근무학과 = b.근무학과 
	SET 
    a.참여백분율 = (b.grouped_cnt / total_work_dept_pf_cnt);
END //
DELIMITER ;

DROP PROCEDURE IF EXISTS insert_work_dept;
DELIMITER $$
CREATE PROCEDURE insert_work_dept(IN 근무교수 SMALLINT , IN 근무학과 SMALLINT) -- work_dept에 대한 삽입 작업 수행
BEGIN
   INSERT INTO work_dept VALUES(NULL, 근무교수, 근무학과, NULL);
   CALL update_pct_time(); -- 각 근무학과별로 참여백분율 갱신
END$$
DELIMITER ;

DROP PROCEDURE IF EXISTS update_work_dept;
DELIMITER $$
CREATE PROCEDURE update_work_dept(IN old_src_근무교수 SMALLINT , IN old_src_근무학과 SMALLINT, IN new_src_근무교수 SMALLINT, 
IN new_src_근무학과 SMALLINT) -- work_dept에 대한 수정 작업 수행
BEGIN
   UPDATE work_dept SET 근무교수 = new_src_근무교수, 근무학과 = new_src_근무학과
   WHERE 근무교수 = old_src_근무교수 AND 근무학과 = old_src_근무학과;
   CALL update_pct_time(); -- 각 근무학과별로 참여백분율 갱신
END$$
DELIMITER ;

DROP PROCEDURE IF EXISTS update_work_dept_old_pk;
DELIMITER $$
CREATE PROCEDURE update_work_dept_old_pk(IN old_src_근무번호 SMALLINT , 
IN new_src_근무교수 SMALLINT, IN new_src_근무학과 SMALLINT) -- work_dept에 대한 수정 작업 수행
BEGIN
   UPDATE work_dept SET 근무교수 = new_src_근무교수, 근무학과 = new_src_근무학과
   WHERE 근무번호 = old_src_근무번호;
   CALL update_pct_time(); -- 각 근무학과별로 참여백분율 갱신
END$$
DELIMITER ;

DROP PROCEDURE IF EXISTS delete_work_dept;
DELIMITER $$
CREATE PROCEDURE delete_work_dept(IN src_근무교수 SMALLINT , IN src_근무학과 SMALLINT) -- work_dept에 대한 삭제 작업 수행
BEGIN
	DELETE FROM work_dept WHERE 근무교수 = src_근무교수 AND 근무학과 = src_근무학과;
	CALL update_pct_time(); -- 각 근무학과별로 참여백분율 갱신
END$$
DELIMITER ;

DROP PROCEDURE IF EXISTS delete_work_dept_pk;
DELIMITER $$
CREATE PROCEDURE delete_work_dept_pk(IN src_근무번호 SMALLINT) -- work_dept에 대한 삭제 작업 수행
BEGIN
	DELETE FROM work_dept WHERE 근무번호 = src_근무번호;
	CALL update_pct_time(); -- 각 근무학과별로 참여백분율 갱신
END$$
DELIMITER ;

INSERT INTO Professor VALUES (NULL, 'PF_Kim', 30, '조교수', '운영체제');
INSERT INTO Professor VALUES (NULL, 'PF_Jin', 40, '부교수', '임베디드');
INSERT INTO Professor VALUES (NULL, 'PF_Park', 50, '정교수', '네트워크');
INSERT INTO Professor VALUES (NULL, 'PF_Lee', 60, '명예교수', '그래픽스');
INSERT INTO Professor VALUES (NULL, 'PF_Roh', 70, '명예교수', '데이터베이스');
INSERT INTO Dept VALUES (NULL, '컴퓨터공학과', '100호', 1);
INSERT INTO Dept VALUES (NULL, '기계과', '101호', 2);
INSERT INTO Dept VALUES (NULL, '전자과', '102호', 3);
INSERT INTO Dept VALUES (NULL, '정보통신학과', '103호', 4);
INSERT INTO Dept VALUES (NULL, '정보시스템과', '104호', 5);
INSERT INTO Graduate VALUES (NULL, 'GD_Kim', 26, '석사', NULL, 1);
INSERT INTO Graduate VALUES (NULL, 'GD_Jin', 27, '석사', 1, 1);
INSERT INTO Graduate VALUES (NULL, 'GD_Park', 28, '석사', NULL, 2);
INSERT INTO Graduate VALUES (NULL, 'GD_Lee', 29, '박사', 3, 3);
INSERT INTO Graduate VALUES (NULL, 'GD_Roh', 30, '박사', NULL, 4);
INSERT INTO Project VALUES (NULL, '교육부', '2020-01-01', '2020-01-30', 1000000, 1);
INSERT INTO Project VALUES (NULL, '국방부', '2020-02-01', '2020-02-29', 2000000, 1);
INSERT INTO Project VALUES (NULL, '국세청', '2020-03-01', '2020-03-30', 3000000, 2);
INSERT INTO Project VALUES (NULL, '고용노동부', '2020-04-01', '2020-04-30', 4000000, 3);
INSERT INTO Project VALUES (NULL, '기상청', '2020-05-01', '2020-05-30', 5000000, 4);

SELECT * FROM Professor;
SELECT * FROM Dept;
SELECT * FROM Graduate;
SELECT * FROM Project;
SELECT * FROM work_dept; -- 교수와 학과간의 근무테이블
SELECT * FROM work_in; -- 교수와 과제 간의 수행 테이블
SELECT * FROM work_prog; -- 대학원생과 과제 간의 수행 테이블

/***
	교수와 학과 간의 근무 테이블은 참여백분율 자동 계산위해 사용자 정의 프로시저 호출로만 수행
    ---
	입력 : 근무교수 아이디, 근무학과 아이디만 입력(insert_work_dept)
	수정 : 변경하고자 하는 근무교수 아이디, 변경하고자 하는 근무학과 아이디, 새로운 근무교수 아이디, 새로운 근무학과 아이디 (update_work_dept)
			or 변경하고자 하는 근무번호, 새로운 근무학과 아이디, 새로운 근무교수 아이디(update_work_dept_old_pk)
	삭제 : 근무교수 아이디, 근무학과 아이디만 입력(delete_work_dept) or 근무번호만 입력(delete_work_dept_pk)
***/
CALL insert_work_dept(1, 1); -- 교수아이디 : 1, 학과 아이디 : 1 레코드 입력 
CALL insert_work_dept(2, 1);
CALL insert_work_dept(3, 3);
CALL insert_work_dept(4, 3);
CALL insert_work_dept(5, 5);

SELECT * FROM work_dept; -- 교수와 학과간의 근무테이블

CALL update_work_dept(1, 1, 1, 2); -- 기존 교수아이디 : 1, 학과 아이디 : 1 인 레코드를 교수아이디 : 1, 학과 아이디 : 2 로 변경
SELECT * FROM work_dept; -- 교수와 학과간의 근무테이블
CALL update_work_dept_old_pk(1, 2, 1); -- 기존 근무번호 : 1 인 레코드를 교수아이디 : 2, 학과 아이디 : 1 로 변경
SELECT * FROM work_dept; -- 교수와 학과간의 근무테이블
CALL delete_work_dept(1, 2); -- 교수아이디 : 1, 학과 아이디 : 2 인 레코드 삭제
SELECT * FROM work_dept; -- 교수와 학과간의 근무테이블

-- 과제는 한 사람 이상의 교수에 의해 수행되므로, 수행교수와 수행과제 항목은 중복을 허용 
INSERT INTO work_in VALUES(NULL, 1, 1); -- 수행교수, 수행과제
INSERT INTO work_in VALUES(NULL, 1, 2); -- 수행교수, 수행과제
INSERT INTO work_in VALUES(NULL, 1, 3); -- 수행교수, 수행과제
INSERT INTO work_in VALUES(NULL, 1, 4); -- 수행교수, 수행과제
INSERT INTO work_in VALUES(NULL, 2, 5); -- 수행교수, 수행과제
SELECT * FROM work_in; -- 교수와 과제 간의 수행 테이블

-- 한 과제는 한 명 이상의 대학원생에 의해 수행되므로, 수행 대학원생과 수행과제 항목은 중복을 허용
INSERT INTO work_prog VALUES(NULL, 1, 1); -- 수행 대학원생, 수행과제
INSERT INTO work_prog VALUES(NULL, 1, 2); -- 수행 대학원생, 수행과제
INSERT INTO work_prog VALUES(NULL, 1, 3); -- 수행 대학원생, 수행과제
INSERT INTO work_prog VALUES(NULL, 2, 1); -- 수행 대학원생, 수행과제
INSERT INTO work_prog VALUES(NULL, 3, 5); -- 수행 대학원생, 수행과제
SELECT * FROM work_prog;
